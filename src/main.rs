mod api;
mod appload;
mod backend;
mod capture;
mod config;
mod http;
mod models;
mod pairing;

use anyhow::{Context, Result};

use appload::AppLoadSocket;
use backend::Backend;
use config::Config;

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let first = args
        .next()
        .context("expected the AppLoad socket path or a capture command as argv[1]")?;

    if first.starts_with("--capture-") {
        return capture::run(&first, args.next().as_deref());
    }

    let config = Config::load()?;
    let socket = AppLoadSocket::connect(&first)?;
    let result = Backend::new(config).run(socket);
    if let Err(err) = &result {
        eprintln!("saver-remarkable: {err:#}");
    }
    result
}
