#![feature(proc_macro_hygiene, decl_macro)]

#[macro_use] extern crate rocket;

use rocket::State;
use rocket::fairing::AdHoc;

use std::process::Command;

struct HookConfig {
    folder: String,
    token: String
}

#[post("/hook/<token>")]
fn hook(token: String, state: State<HookConfig>) -> Result<String, i32> {
    if token != state.token {
        return Err(500);
    }
    let expanded_path = expanduser::expanduser(&state.folder)
        .map_err(|_| 500)?;

    let mut update_git_command = Command::new("sh");
    update_git_command.arg("-c")
        .arg("git reset --hard && git pull")
        .current_dir(&expanded_path);

    let status = update_git_command.status()
        .map_err(|_| 500)?;

    match status.success() {
        true => Ok(format!("Done")),
        false => Err(500)
    }
}

fn main() {
    println!("Remember to set the variables in Rocket.toml");
    rocket::ignite()
        .attach(AdHoc::on_attach("Env", |rocket| {
            println!("Adding token & folder managed state from Rocket.toml");
            let token = rocket.config()
                .get_str("token")
                .expect("Expecting `token` in global Rocket.toml");

            let folder = rocket.config()
                .get_str("folder")
                .expect("Expecting `folder` in global Rocket.toml");

            let state = HookConfig { 
                token: token.to_string(), 
                folder: folder.to_string() 
            };

            Ok(rocket.manage(state))
        }))
        .mount("/", routes![hook]).launch();
}
