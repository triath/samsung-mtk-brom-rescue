# Reading MediaTek's expdb (Exception Database)

The `expdb` partition (~40 MiB on the A14) contains MediaTek's boot-time exception records. It is the phone's own crash log and it tells you exactly where boot dies.

## How to read it

Dump the partition via BROM/mtkclient, then:

```bash
strings -n 6 expdb.cur | grep -iE 'panic|assert|reboot|wdt|fail|error|preloader|lk|kernel|exception|abort|secure'
```

## What to look for

### Boot flow trace

```
[SBC] cert verify, part = lk, img = lk...ok
[SBC] cert verify, part = tee1, img = atf...ok
[SBC] cert verify, part = gz1, img = gz...ok
[BLDR] bldr load tee part ret=0x0, addr=0x48C00DC0
[BLDR] Loading LK Partition...
[BLDR] Others, jump to ATF
[BLDR] jump to 0x48200000
```

If you see all `cert verify...ok` lines and `jump to ATF`, the preloader and all co-processor images are valid. The crash is happening after ATF starts, in ATF itself or in lk.

### Watchdog reset records

```
RAM_CONSOLE detect abnormal boot wdt_status:0x6
```

Multiple occurrences = the phone is in a watchdog reset loop. Each reset re-runs the preloader, including its USB download window. That is your BROM access.

### Build identification

```
[BLDR] Build Time: 20260811-130233
```

This tells you which preloader version is actually running, independent of what you think you flashed.

### Anti-rollback version

```
get_anti_rollback_secure_group_ver: SG region value is (0x3)
[ver]ver:(verk,verc,otp)=(3, 3, 3) ok
```

The `otp` value is burned into hardware and cannot be lowered. If your target firmware has a lower version than OTP, anti-rollback will block it permanently.

## What expdb won't tell you

- Whether a write committed successfully (check by reading back the partition and hashing)
- The current state of `super` (it's too large to reason about from crash logs)
- Anything about the Auth rejection. That is in the Download-mode agent's response, not in expdb
