// miss-sample: run a command and sample its loads that miss a cache level, precisely (PEBS), with the address of the load
// instruction and the data address it read.  No perf binary: perf_event_open directly, which an unprivileged user may do on its
// own child with kernel.perf_event_paranoid <= 2 (user space only).  Only the child's main thread is sampled (no inherit): with
// prelowering off that is the evaluator.
//
//   miss-sample OUT.txt RAWEVENT PERIOD -- cmd args...
//   RAWEVENT  Skylake MEM_LOAD_RETIRED: 0x20d1 L3 miss, 0x10d1 L2 miss, 0x08d1 L1 miss
//
// MISS_PRECISE (default 2) is perf's precise_ip: under a hypervisor without PEBS (WSL2: cpu/caps/max_precise is 0) it must be 0, and then
// the ip skids a few instructions past the load (usually onto the first use of what it read) and the data address is 0.
//
// OUT.txt gets "ip addr" per sample (hex), then the child's /proc/PID/maps after "== maps" (the newest taken while it ran), to place both.
#define _GNU_SOURCE
#include <linux/perf_event.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { kDataPages = 256 }; // a power of two: 1 MiB of samples between drains

static FILE *out;
static unsigned long long nSamples, nLost;

static void drain(struct perf_event_mmap_page *meta) {
  char *data = (char *)meta + meta->data_offset;
  uint64_t size = meta->data_size, head = __atomic_load_n(&meta->data_head, __ATOMIC_ACQUIRE), tail = meta->data_tail;
  while (tail < head) {
    struct perf_event_header h;
    char rec[256];
    for (size_t i = 0; i < sizeof h; i++) ((char *)&h)[i] = data[(tail + i) % size];
    if (h.size > sizeof rec || h.size < sizeof h) break;
    for (size_t i = 0; i < h.size; i++) rec[i] = data[(tail + i) % size];
    if (h.type == PERF_RECORD_SAMPLE) {
      uint64_t ip, addr;
      memcpy(&ip, rec + sizeof h, 8);
      memcpy(&addr, rec + sizeof h + 8, 8);
      fprintf(out, "%llx %llx\n", (unsigned long long)ip, (unsigned long long)addr);
      nSamples++;
    } else if (h.type == PERF_RECORD_LOST) {
      uint64_t lost;
      memcpy(&lost, rec + sizeof h + 8, 8);
      nLost += lost;
    }
    tail += h.size;
  }
  __atomic_store_n(&meta->data_tail, tail, __ATOMIC_RELEASE);
}

int main(int argc, char **argv) {
  if (argc < 6 || strcmp(argv[4], "--")) {
    fprintf(stderr, "usage: miss-sample OUT.txt RAWEVENT PERIOD -- cmd args...\n");
    return 2;
  }
  out = fopen(argv[1], "w");
  if (!out) { perror(argv[1]); return 2; }
  int go[2];
  if (pipe(go)) { perror("pipe"); return 2; }
  pid_t child = fork();
  if (child == 0) { // wait until the counter is attached, then become the command; counting starts at the exec
    char c;
    close(go[1]);
    if (read(go[0], &c, 1) != 1) _exit(127);
    execvp(argv[5], argv + 5);
    perror(argv[5]);
    _exit(127);
  }
  close(go[0]);
  struct perf_event_attr a;
  memset(&a, 0, sizeof a);
  a.size = sizeof a;
  a.type = PERF_TYPE_RAW;
  a.config = strtoull(argv[2], 0, 16);
  a.sample_period = strtoull(argv[3], 0, 10);
  a.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_ADDR;
  a.precise_ip = getenv("MISS_PRECISE") ? (unsigned)atoi(getenv("MISS_PRECISE")) & 3 : 2;
  a.disabled = 1;
  a.enable_on_exec = 1;
  a.exclude_kernel = 1;
  a.exclude_hv = 1;
  a.wakeup_events = 64;
  int fd = (int)syscall(SYS_perf_event_open, &a, child, -1, -1, 0);
  if (fd < 0) { perror("perf_event_open"); kill(child, SIGKILL); return 2; }
  long page = sysconf(_SC_PAGESIZE);
  struct perf_event_mmap_page *meta = mmap(0, (size_t)page * (1 + kDataPages), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (meta == MAP_FAILED) { perror("mmap"); kill(child, SIGKILL); return 2; }
  char maps[64];
  snprintf(maps, sizeof maps, "/proc/%d/maps", (int)child);
  if (write(go[1], "g", 1) != 1) { perror("write"); return 2; }
  close(go[1]);
  char *saved = 0;
  time_t lastMap = 0;
  int status = 0;
  for (;;) {
    struct pollfd p = {fd, POLLIN, 0};
    poll(&p, 1, 200);
    drain(meta);
    time_t now = time(0);
    if (now != lastMap) { // the newest map before the child exits places every ip and address (arena slabs are mapped as it runs)
      FILE *m = fopen(maps, "r");
      if (m) {
        char *buf = 0;
        size_t len = 0;
        FILE *mem = open_memstream(&buf, &len);
        char line[4096];
        while (fgets(line, sizeof line, m)) fputs(line, mem);
        fclose(mem);
        fclose(m);
        if (len) { free(saved); saved = buf; } else free(buf); // a zombie's map is empty: keep the last real one
      }
      lastMap = now;
    }
    pid_t w = waitpid(child, &status, WNOHANG);
    if (w == child) break;
  }
  drain(meta);
  fprintf(out, "== maps\n%s", saved ? saved : "");
  fclose(out);
  fprintf(stderr, "miss-sample: %llu samples, %llu lost; child exit %d\n", nSamples, nLost, WIFEXITED(status) ? WEXITSTATUS(status) : -1);
  return 0;
}
