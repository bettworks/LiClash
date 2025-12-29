use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::{io, thread};
use tokio::sync::RwLock;
use warp::{Filter, Reply};

mod process;
use process::ProcessHandle;

const LISTEN_PORT: u16 = 47890;
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(65);
const CHECK_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
}

fn sha256_file(path: &str) -> Result<String, Error> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];

    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<ProcessHandle>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));

// 心跳相关
static LAST_HEARTBEAT: Lazy<Arc<RwLock<Instant>>> =
    Lazy::new(|| Arc::new(RwLock::new(Instant::now())));

fn start(start_params: StartParams) -> impl Reply {
    let sha256 = sha256_file(start_params.path.as_str()).unwrap_or("".to_string());
    if sha256 != env!("TOKEN") {
        return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256,  env!("TOKEN"),);
    }
    stop();
    
    // 重置心跳时间
    tokio::spawn(async {
        *LAST_HEARTBEAT.write().await = Instant::now();
    });
    
    let mut process = PROCESS.lock().unwrap();
    let args = vec![start_params.arg];
    match ProcessHandle::spawn(&start_params.path, &args) {
        Ok(handle) => {
            #[cfg(not(windows))]
            {
                // 非Windows平台：尝试获取stderr
                let mut handle_mut = handle;
                if let Some(mut stderr) = handle_mut.stderr() {
                    let stderr_handle = Arc::clone(&LOGS);
                    thread::spawn(move || {
                        for line in stderr.lines() {
                            match line {
                                Ok(output) => {
                                    let mut log_buffer = stderr_handle.lock().unwrap();
                                    if log_buffer.len() == 100 {
                                        log_buffer.pop_front();
                                    }
                                    log_buffer.push_back(format!("{}\n", output));
                                }
                                Err(_) => {
                                    break;
                                }
                            }
                        }
                    });
                }
                *process = Some(handle_mut);
            }
            #[cfg(windows)]
            {
                // Windows平台：直接保存handle
                *process = Some(handle);
            }
            "".to_string()
        }
        Err(e) => {
            log_message(e.clone());
            e
        }
    }
}

fn stop() -> impl Reply {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut handle) = process.take() {
        let _ = handle.kill();
        let _ = handle.wait();
    }
    *process = None;
    "".to_string()
}

fn heartbeat() -> impl Reply {
    tokio::spawn(async {
        *LAST_HEARTBEAT.write().await = Instant::now();
    });
    "".to_string()
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 100 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> impl Reply {
    let log_buffer = LOGS.lock().unwrap();
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

pub async fn run_service() -> anyhow::Result<()> {
    // 启动心跳监控器
    let heartbeat_monitor = {
        let process_handle = Arc::clone(&PROCESS);
        let last_heartbeat = Arc::clone(&LAST_HEARTBEAT);
        tokio::spawn(async move {
            let mut last_check_time = Instant::now();
            loop {
                tokio::time::sleep(CHECK_INTERVAL).await;

                let now = Instant::now();
                let check_elapsed = now.duration_since(last_check_time);
                last_check_time = now;

                // 检测系统休眠唤醒：两次检查之间的间隔远大于 CHECK_INTERVAL
                if check_elapsed > Duration::from_secs(60) {
                    log::info!(
                        "检测到系统休眠唤醒（检查间隔: {}s），重置心跳计时器",
                        check_elapsed.as_secs()
                    );
                    *last_heartbeat.write().await = Instant::now();
                    continue;
                }

                let elapsed = last_heartbeat.read().await.elapsed();
                if elapsed > HEARTBEAT_TIMEOUT {
                    log::warn!(
                        "超过 {} 秒未收到主程序心跳，停止 Clash 核心（服务继续运行）",
                        HEARTBEAT_TIMEOUT.as_secs()
                    );

                    // 只停止 Clash 核心，不关闭服务
                    let mut process = process_handle.lock().unwrap();
                    if let Some(mut handle) = process.take() {
                        if let Err(e) = handle.kill() {
                            log::error!("心跳超时停止 Clash 失败: {}", e);
                        } else {
                            log::info!("心跳超时，Clash 核心已停止，等待主程序重连");
                        }
                        let _ = handle.wait();
                    }

                    // 重置心跳时间，避免反复触发
                    *last_heartbeat.write().await = Instant::now();
                } else {
                    log::debug!("心跳正常，距离上次心跳: {}s", elapsed.as_secs());
                }
            }
        })
    };

    let api_ping = warp::get().and(warp::path("ping")).map(|| env!("TOKEN"));

    let api_heartbeat = warp::post()
        .and(warp::path("heartbeat"))
        .map(|| heartbeat());

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post().and(warp::path("stop")).map(|| stop());

    let api_logs = warp::get().and(warp::path("logs")).map(|| get_logs());

    tokio::select! {
        result = warp::serve(api_ping.or(api_heartbeat).or(api_start).or(api_stop).or(api_logs))
            .run(([127, 0, 0, 1], LISTEN_PORT)) => {
            result
        }
        _ = heartbeat_monitor => {
            Ok(())
        }
    }
}
