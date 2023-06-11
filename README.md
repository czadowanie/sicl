# SiCL
![logo](sicl_logo.svg)  
**Surprisingly simple command-based launcher**  

In my experience using .desktop entries to launch apps through _dmenu/bemenu/fzf/whathaveyou_
is somewhat inefficient (it takes time to locate and read all of those files, especially right after startup) 
and the result is very noisy thanks to both native and wine applications creating them willy-nilly. 
The main idea behind this tool is that you can specify a bunch of aliases 
to commands in a single csv file like so:

```csv
firefox;/usr/bin/firefox
bluetooth;/usr/bin/blueman-manager
gimp;/usr/bin/gimp
steam;flatpak run com.valvesoftware.Steam
virtmanager;/usr/bin/virt-manager
helvum;/usr/bin/helvum
inkscape;/usr/bin/inkscape
```

And it will pass them to your favorite menu program.

# Configuration

The default configuration is provided in [sicl.json](./sicl.json)

- `menu_cmd` - menu program you want to use
- `csv_path` - an absolute path to where you want to store all of the aliases, when set to null it's going touse "$HOME/.local/share/sicl.csv"
