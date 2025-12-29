// Clash IPC 网络通信消息定义
//
// 定义 Dart 与 Rust 之间的 IPC 通信消息

use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};

// REST API 调用

// Dart → Rust：通过 IPC 发送 GET 请求
#[derive(Deserialize, DartSignal)]
pub struct IpcGetRequest {
    pub request_id: i64,
    pub path: String,
}

// Dart → Rust：通过 IPC 发送 POST 请求
#[derive(Deserialize, DartSignal)]
pub struct IpcPostRequest {
    pub request_id: i64,
    pub path: String,
    pub body: Option<String>,
}

// Dart → Rust：通过 IPC 发送 PUT 请求
#[derive(Deserialize, DartSignal)]
pub struct IpcPutRequest {
    pub request_id: i64,
    pub path: String,
    pub body: Option<String>,
}

// Dart → Rust：通过 IPC 发送 PATCH 请求
#[derive(Deserialize, DartSignal)]
pub struct IpcPatchRequest {
    pub request_id: i64,
    pub path: String,
    pub body: Option<String>,
}

// Dart → Rust：通过 IPC 发送 DELETE 请求
#[derive(Deserialize, DartSignal)]
pub struct IpcDeleteRequest {
    pub request_id: i64,
    pub path: String,
}

// Rust → Dart：IPC 请求响应
#[derive(Serialize, RustSignal)]
pub struct IpcResponse {
    // 请求 ID（用于匹配请求和响应）
    pub request_id: i64,
    // HTTP 状态码
    pub status_code: u16,
    // 响应体（JSON 字符串）
    pub body: String,
    // 是否成功
    pub success: bool,
    // 错误消息（如果有）
    pub error_message: Option<String>,
}

// WebSocket 流式数据

// Dart → Rust：开始监听 Clash 日志
#[derive(Deserialize, DartSignal)]
pub struct StartLogStream;

// Dart → Rust：停止监听 Clash 日志
#[derive(Deserialize, DartSignal)]
pub struct StopLogStream;

// Rust → Dart：Clash 日志数据
#[derive(Serialize, RustSignal)]
pub struct IpcLogData {
    pub log_type: String,
    pub payload: String,
}

// Dart → Rust：开始监听流量数据
#[derive(Deserialize, DartSignal)]
pub struct StartTrafficStream;

// Dart → Rust：停止监听流量数据
#[derive(Deserialize, DartSignal)]
pub struct StopTrafficStream;

// Rust → Dart：流量数据
#[derive(Serialize, RustSignal)]
pub struct IpcTrafficData {
    pub upload: u64,
    pub download: u64,
}

// Rust → Dart：流操作结果
#[derive(Serialize, RustSignal)]
pub struct StreamResult {
    pub success: bool,
    pub error_message: Option<String>,
}
