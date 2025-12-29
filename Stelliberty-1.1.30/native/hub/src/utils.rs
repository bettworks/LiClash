pub mod init_logger;
mod signals;

pub fn init() {
    init_logger::setup_logger();
    signals::init();
}
