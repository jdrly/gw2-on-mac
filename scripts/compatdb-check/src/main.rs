//! Each file named on the command line must be a table of compatdb rules that
//! `Table::parse_strict` reads without a diagnostic and that `Display` writes
//! back as the same text, the file's last line break aside.

use std::{env, fs, process::ExitCode};

use compatdb_core::Table;

fn main() -> ExitCode {
    let paths: Vec<String> = env::args().skip(1).collect();
    let mut failed = paths.is_empty();
    if failed {
        eprintln!("FAIL no rules files named");
    }
    for path in paths {
        let text = match fs::read_to_string(&path) {
            Ok(text) => text,
            Err(error) => {
                eprintln!("FAIL {path}: {error}");
                failed = true;
                continue;
            }
        };
        match Table::parse_strict(&text) {
            Err(error) => {
                eprintln!("FAIL {path}: {error}");
                failed = true;
            }
            Ok(table) => {
                let back = format!("{table}\n");
                if back == text {
                    println!("ok   {path}: {} rules", table.rules().len());
                } else {
                    eprintln!("FAIL {path}: writes back as\n{back}");
                    failed = true;
                }
            }
        }
    }
    if failed { ExitCode::FAILURE } else { ExitCode::SUCCESS }
}
