#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if std::env::args().any(|arg| arg == "--sync-once") {
        match gallery_lib::sync_once_cli() {
            Ok(summary) => println!("{summary}"),
            Err(error) => { eprintln!("{error}"); std::process::exit(1); }
        }
    } else {
        gallery_lib::run()
    }
}
