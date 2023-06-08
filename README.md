# SiCL
![logo](sicl_logo.svg)
**Surprisingly simple command-based launcher**

In my experience using .desktop entries to launch apps through dmenu/bemenu/fzf/whathaveyou 
is somewhat inefficient (it takes time to locate and read all of those files, especially right after startup) 
and the result is very noisy thanks to both native and wine applications creating them willy-nilly. 
The main idea behind this tool is that instead of using .desktop entries to launch apps you can specify a bunch of aliases 
to commands in a single file  like so:

'''csv
firefox;/usr/bin/firefox
bluetooth;/usr/bin/blueman-manager
gimp;/usr/bin/gimp
steam;flatpak run com.valvesoftware.Steam
virtmanager;/usr/bin/virt-manager
helvum;/usr/bin/helvum
inkscape;/usr/bin/inkscape
'''
