

```
sudo dnf copr enable lihaohong/yazi
```

```
sudo dnf install yazi
```


Run this, it will create the config file, then copy over other config

```
ya pkg add BennyOe/tokyo-night
```

.bashrc
```
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}
```
