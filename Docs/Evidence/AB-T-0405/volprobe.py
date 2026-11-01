# The engine's VolumeProbe read (mlx-engine-swift MLXServeCore/VolumeProbe.swift): 256 MB of a large file with F_NOCACHE,
# in 16 MB chunks, from an offset past the first GB so a recent read of the head can't help. Prints bytes per second.
import fcntl, os, sys, time
F_NOCACHE = 48
path = sys.argv[1]
fd = os.open(path, os.O_RDONLY)
fcntl.fcntl(fd, F_NOCACHE, 1)
size = os.fstat(fd).st_size
offset = int(sys.argv[2]) if len(sys.argv) > 2 else min(1 << 30, max(0, size - (256 << 20)))
os.lseek(fd, offset, 0)
total, start = 0, time.perf_counter()
while total < 256 << 20:
    b = os.read(fd, 16 << 20)
    if not b: break
    total += len(b)
dt = time.perf_counter() - start
print(f"{path}: {total/dt/1e9:.2f} GB/s ({total>>20} MB in {dt:.3f} s from offset {offset>>20} MB)")
