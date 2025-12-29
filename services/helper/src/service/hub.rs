use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{Error, Read};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use warp::{Filter, Reply};

use crate::service::process::ProcessHandle;

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
    let last_heartbeat = Arc::clone(&LAST_HEARTBEAT);
    tokio::spawn(async move {
        *last_heartbeat.write().await = Instant::now();
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
                    let stderr_handle: Arc<Mutex<VecDeque<String>>> = Arc::clone(&LOGS);
                    std::thread::spawn(move || {
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
            let error_msg: String = e.clone();
            log_message(error_msg.clone());
            error_msg
        }
    }
}

fn stop() -> impl Reply {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut handle) = process.take() {
        // 先终止进程，然后等待退出
        // 注意：kill() 会关闭 handle，所以 wait() 需要在 kill() 之前或使用不同的方式
        let _: Result<(), String> = handle.kill();
        // wait() 在 kill() 之后可能失败（因为 handle 已关闭），这是预期的
        let _: Result<(), String> = handle.wait();
    }
    *process = None;
    "".to_string()
}

fn heartbeat() -> impl Reply {
    let last_heartbeat = Arc::clone(&LAST_HEARTBEAT);
    tokio::spawn(async move {
        *last_heartbeat.write().await = Instant::now();
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
        let process_handle: Arc<Mutex<Option<ProcessHandle>>> = Arc::clone(&PROCESS);
        let last_heartbeat: Arc<RwLock<Instant>> = Arc::clone(&LAST_HEARTBEAT);
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
                        // 终止进程
                        if let Err(e) = handle.kill() {
                            log::error!("心跳超时停止 Clash 失败: {}", e);
                        } else {
                            log::info!("心跳超时，Clash 核心已停止，等待主程序重连");
                        }
                        // wait() 在 kill() 之后可能失败（因为 handle 已关闭），这是预期的
                        let _: Result<(), String> = handle.wait();
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
        _ = warp::serve(api_ping.or(api_heartbeat).or(api_start).or(api_stop).or(api_logs))
            .run(([127, 0, 0, 1], LISTEN_PORT)) => {
            // warp::serve().run() 返回 ()，表示服务器运行直到被关闭
            Ok(())
        }
        _ = heartbeat_monitor => {
            Ok(())
        }
    }
}
