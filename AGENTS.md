## Disk I/O: keep throwaway data off the drives

Test databases, sandboxes and temp files must not wear out the developer's drives.

- **Throwaway data goes in RAM.** Put scratch files, mutation-testing sandboxes (Stryker
  `tempDirName`) and test-only temp directories under `$DEV_SCRATCH` (fall back to the system temp
  directory when it is unset). Delete what you create when the run ends.
- **Test databases run on a capped tmpfs at the image's `VOLUME` path** (`postgres:18*`:
  `/var/lib/postgresql`; `postgres:16/17` and `pgvector:*-pg17`: `/var/lib/postgresql/data`;
  `mysql:8*`: `/var/lib/mysql`; check others with `docker image inspect -f '{{json .Config.Volumes}}'`),
  `size=2g`, with Postgres durability off: `-c fsync=off -c synchronous_commit=off -c full_page_writes=off`.
- **Every container you start, you remove.** Use `docker run --rm`, Testcontainers with Ryuk enabled,
  or explicit teardown in a `finally`/`trap`. Never leave a hand-started database running after your
  task. A database you mean to keep gets the label `dev.keep=true`.
- **Generators and tools never rewrite a file whose bytes did not change**, write any manifest once per
  run (not once per file), and verify drift in memory rather than by rendering everything to a temp
  directory.
- **Run the narrowest tests that prove the change** while iterating (one module, the affected test
  classes); run the full suite once, before the PR.
- **No background processes outlive the task.** Kill test watchers, dev servers and sandboxes you
  started before you finish.
