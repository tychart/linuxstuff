```
sudo apt update
sudo apt install nfs-common
```

```
UUID=29887133-fefe-40d5-b689-1173351ce553 /mnt/storagedrive  ext4  defaults,nofail  0  2

192.168.10.31:/mnt/pool/nas/media /mnt/media nfs nofail,noatime,nolock,intr,actimeo=60 0 0
192.168.10.31:/mnt/pool/nas/programs /mnt/programs nfs nofail,noatime,nolock,intr,actimeo=60 0 0
192.168.10.31:/mnt/pool/nas/documents /mnt/documents nfs nofail,noatime,nolock,intr,actimeo=60 0 0
```
