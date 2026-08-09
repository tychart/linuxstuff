## Syncthing Setup

### Fedora 44


Install Package:
```bash
sudo dnf install syncthing
```


For tray support, use extension from Gnome Extension Manager:
```text
Syncthing Indicator by 2nv2u
```

Go to `http://192.168.10.33:8384/`, then add the new device, then share the folder.

Back on the local machine, go and accept the folder share and put in the filepath. Make sure to use:

```path
/home/tychart/Documents/syncthingshared
```

As the path, if just Documents is selected, then entire documents folder will be synced.