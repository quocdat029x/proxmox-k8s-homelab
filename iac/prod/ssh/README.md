# Place your SSH **public** key here

Copy your key:            cp ~/.ssh/id_ed25519.pub ./ssh/
Or point the root module at another path via `ssh_public_key_path`
in `terraform.tfvars` (default: `./ssh/id_ed25519.pub`).

This public key is injected into every VM's cloud-init (`ubuntu` user).

The matching **private key never belongs in this repo** — `.gitignore`
blocks everything in `ssh/` except this README.
