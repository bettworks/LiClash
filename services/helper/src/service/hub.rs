use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{Error, Read};
use std::sync::{Arc, Mutex};
use warp::{Filter, Reply};

use crate::service::process::ProcessHandle;

const LISTEN_PORT: u16 = 47890;

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

fn start(start_params: StartParams) -> impl Reply {
    let sha256 = sha256_file(start_params.path.as_str()).unwrap_or("".to_string());
    if sha256 != env!("TOKEN") {
        return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256,  env!("TOKEN"),);
    }
    stop();
    
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
        let _: Result<(), String> = handle.kill();
        let _: Result<(), String> = handle.wait();
    }
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
    let api_ping = warp::get().and(warp::path("ping")).map(|| env!("TOKEN"));

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post().and(warp::path("stop")).map(|| stop());

    let api_logs = warp::get().and(warp::path("logs")).map(|| get_logs());

    warp::serve(api_ping.or(api_start).or(api_stop).or(api_logs))
        .run(([127, 0, 0, 1], LISTEN_PORT))
        .await;
    
    Ok(())
}
