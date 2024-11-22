{
  disko.devices = {
    disk = {
      my-disk = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            zfs-pool = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";  # Recommended to name your ZFS pool
                # Consider adding these options
                options = {
                  compression = "zstd";  # Good compression with low overhead
                  atime = "off";  # Improves performance
                  xattr = "sa";  # Small performance improvement
                };
              };
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        # Consider these additional pool-level options
        options = {
          ashift = "12";  # Optimal for modern drives
          autotrim = "on";  # Good for SSDs
        };
      };
    };
  };
}
