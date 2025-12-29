// Clash 直接进程管理的消息定义
//
// 定义 Dart 与 Rust 之间的通信消息

use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};

// Dart → Rust：启动 Clash 进程
#[derive(Deserialize, DartSignal)]
pub struct StartClashProcess {
    pub executable_path: String,
    pub args: Vec<String>,
}

// Dart → Rust：停止 Clash 进程
#[derive(Deserialize, DartSignal)]
pub struct StopClashProcess;

// Rust → Dart：Clash 进程操作结果
#[derive(Serialize, RustSignal)]
pub struct ClashProcessResult {
    pub success: bool,
    pub error_message: Option<String>,
    pub pid: Option<u32>,
}
