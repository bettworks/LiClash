#[cfg(windows)]
use std::ffi::OsStr;
#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;
#[cfg(windows)]
use std::ptr;
#[cfg(windows)]
use winapi::shared::minwindef::FALSE;
#[cfg(windows)]
use winapi::um::handleapi::CloseHandle;
#[cfg(windows)]
use winapi::um::jobapi2::{
    AssignProcessToJobObject, CreateJobObjectW, SetInformationJobObject,
};
#[cfg(windows)]
use winapi::um::processthreadsapi::{
    CreateProcessW, PROCESS_INFORMATION, ResumeThread, STARTUPINFOW, TerminateProcess,
};
#[cfg(windows)]
use winapi::um::winbase::{CREATE_NO_WINDOW, CREATE_SUSPENDED, STARTF_USESHOWWINDOW};
#[cfg(windows)]
use winapi::um::winnt::{
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
};
#[cfg(windows)]
use winapi::um::winuser::SW_HIDE;

#[cfg(not(windows))]
use std::io::BufRead;
#[cfg(not(windows))]
use std::process::{Child, Command, Stdio};

pub struct ProcessHandle {
    #[cfg(windows)]
    process_handle: winapi::um::winnt::HANDLE,
    #[cfg(windows)]
    job_handle: winapi::um::winnt::HANDLE,
    #[cfg(not(windows))]
    child: Child,
}

// Windows HANDLE 类型实际上是线程安全的，可以安全地在线程间传递
// 我们需要手动实现 Send trait
unsafe impl Send for ProcessHandle {}

impl ProcessHandle {
    #[cfg(windows)]
    pub fn spawn_windows(
        executable_path: &str,
        args: &[String],
    ) -> Result<ProcessHandle, String> {
        unsafe {
            // 构建命令行
            let mut command_line = format!("\"{}\"", executable_path);
            for arg in args {
                command_line.push(' ');
                if arg.contains(' ') {
                    command_line.push_str(&format!("\"{}\"", arg));
                } else {
                    command_line.push_str(arg);
                }
            }

            let mut command_line_wide: Vec<u16> = OsStr::new(&command_line)
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();

            // 创建 Job Object（确保子进程跟随父进程终止）
            let job_handle = CreateJobObjectW(ptr::null_mut(), ptr::null());
            if job_handle.is_null() {
                return Err("创建 Job Object 失败".to_string());
            }

            let mut job_info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
            job_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

            if SetInformationJobObject(
                job_handle,
                winapi::um::winnt::JobObjectExtendedLimitInformation,
                &mut job_info as *mut _ as *mut _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) == FALSE
            {
                CloseHandle(job_handle);
                return Err("设置 Job Object 信息失败".to_string());
            }

            // 配置启动信息（隐藏窗口）
            let mut startup_info: STARTUPINFOW = std::mem::zeroed();
            startup_info.cb = std::mem::size_of::<STARTUPINFOW>() as u32;
            startup_info.dwFlags = STARTF_USESHOWWINDOW;
            startup_info.wShowWindow = SW_HIDE as u16;

            let mut process_info: PROCESS_INFORMATION = std::mem::zeroed();

            // 创建进程（挂起状态，无窗口）
            if CreateProcessW(
                ptr::null(),
                command_line_wide.as_mut_ptr(),
                ptr::null_mut(),
                ptr::null_mut(),
                FALSE,
                CREATE_NO_WINDOW | CREATE_SUSPENDED,
                ptr::null_mut(),
                ptr::null(),
                &mut startup_info,
                &mut process_info,
            ) == FALSE
            {
                CloseHandle(job_handle);
                return Err("创建进程失败".to_string());
            }

            // 将进程分配到 Job Object
            if AssignProcessToJobObject(job_handle, process_info.hProcess) == FALSE {
                TerminateProcess(process_info.hProcess, 1);
                CloseHandle(process_info.hProcess);
                CloseHandle(process_info.hThread);
                CloseHandle(job_handle);
                return Err("分配进程到 Job Object 失败".to_string());
            }

            // 恢复进程运行
            if ResumeThread(process_info.hThread) == u32::MAX {
                TerminateProcess(process_info.hProcess, 1);
                CloseHandle(process_info.hProcess);
                CloseHandle(process_info.hThread);
                CloseHandle(job_handle);
                return Err("恢复进程线程失败".to_string());
            }

            CloseHandle(process_info.hThread);

            Ok(ProcessHandle {
                process_handle: process_info.hProcess,
                job_handle,
            })
        }
    }

    #[cfg(not(windows))]
    pub fn spawn_unix(executable_path: &str, args: &[String]) -> Result<ProcessHandle, String> {
        let mut cmd = Command::new(executable_path);
        cmd.args(args);
        cmd.stderr(Stdio::piped());
        cmd.stdout(Stdio::piped());

        match cmd.spawn() {
            Ok(child) => Ok(ProcessHandle { child }),
            Err(e) => Err(format!("启动进程失败: {}", e)),
        }
    }

    pub fn spawn(executable_path: &str, args: &[String]) -> Result<ProcessHandle, String> {
        #[cfg(windows)]
        {
            Self::spawn_windows(executable_path, args)
        }
        #[cfg(not(windows))]
        {
            Self::spawn_unix(executable_path, args)
        }
    }

    #[cfg(windows)]
    pub fn kill(&mut self) -> Result<(), String> {
        unsafe {
            // 关闭 Job Object 会自动终止所有子进程
            if !self.job_handle.is_null() {
                CloseHandle(self.job_handle);
                self.job_handle = ptr::null_mut();
            }
            // 终止主进程
            if !self.process_handle.is_null() {
                TerminateProcess(self.process_handle, 1);
                CloseHandle(self.process_handle);
                self.process_handle = ptr::null_mut();
            }
        }
        Ok(())
    }

    #[cfg(not(windows))]
    pub fn kill(&mut self) -> Result<(), String> {
        self.child.kill().map_err(|e| format!("终止进程失败: {}", e))
    }

    #[cfg(windows)]
    pub fn wait(&mut self) -> Result<(), String> {
        unsafe {
            // 先等待进程退出
            if !self.process_handle.is_null() {
                winapi::um::synchapi::WaitForSingleObject(self.process_handle, u32::MAX);
                CloseHandle(self.process_handle);
                self.process_handle = ptr::null_mut();
            }
            // 然后关闭 Job Object（如果还没关闭）
            if !self.job_handle.is_null() {
                CloseHandle(self.job_handle);
                self.job_handle = ptr::null_mut();
            }
        }
        Ok(())
    }

    #[cfg(not(windows))]
    pub fn wait(&mut self) -> Result<(), String> {
        self.child.wait().map_err(|e| format!("等待进程失败: {}", e))?;
        Ok(())
    }

    #[cfg(not(windows))]
    pub fn stderr(&mut self) -> Option<std::io::BufReader<&mut std::process::ChildStderr>> {
        self.child.stderr.as_mut().map(|s| std::io::BufReader::new(s))
    }

    #[cfg(windows)]
    pub fn stderr(&mut self) -> Option<()> {
        // Windows下通过命名管道获取stderr，这里简化处理
        None
    }
}

impl Drop for ProcessHandle {
    fn drop(&mut self) {
        // 确保进程被终止
        let _ = self.kill();
        let _ = self.wait();
    }
}

