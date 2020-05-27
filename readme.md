Remote control for your projects
================================

`rctl` is a remote controller for your projects.


Installation
------------

- Clone locally: `git clone 'https://github.com/mmvsk/rctl' $HOME/.rctl`
- If your'e using ZSH (`[ "$SHELL" = "/bin/zsh" ] && echo "yes" || echo "ni"`):
	- `echo 'export PATH="$PATH:$HOME/.rctl/bin' >> ~/.zshrc"`
	- `echo 'source "$HOME/.rctl/rctl.compdef' >> ~/.zshrc"`
- If not, add `export PATH="$PATH:$HOME/.rctl/bin"` to your shell rc
- I also recommend to `alias www="rctl"`, as it's easier to type


Usage
-----

- See `rctl help`
- See `vi ~/.rctl/rctl.bash`
