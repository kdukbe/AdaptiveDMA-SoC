# AdaptiveDMA-SoC 레지스터 맵

모든 레지스터는 32-bit이며, 주소는 기준 주소로부터의 byte offset입니다.
AXI4-Lite 주소 폭은 7-bit이고 사용 범위는 `0x00`~`0x7C`입니다. Reset은 active-low `RSTN`입니다.

## 레지스터 목록

| Offset | 이름 | 접근 | 설명 |
|---:|---|---|---|
| `0x00` | `CTRL` | WO | Start 및 soft reset 명령 |
| `0x04` | `STATUS` | RO | busy, done, error |
| `0x08` | `SRC_ADDR` | RW | Source DDR 주소 |
| `0x0C` | `DST_ADDR` | RW | Destination DDR 주소 |
| `0x10` | `TRANSFER_BYTES` | RW | 전체 복사 길이, byte 단위 |
| `0x14` | `CYC_TOTAL` | RO | 전체 DMA busy cycle 수 |
| `0x18` | `CYC_READ` | RO | RDMA busy cycle 수 |
| `0x1C` | `CYC_WRITE` | RO | WDMA busy cycle 수 |
| `0x20` | `READ_BEATS` | RO | R handshake 횟수 |
| `0x24` | `WRITE_BEATS` | RO | W handshake 횟수 |
| `0x28` | `DMA_CFG` | RW | Burst 및 outstanding 상한 |
| `0x2C` | `RBR_CFG` | RW | Read/Write RBR delta 값 |
| `0x30` | `RBR_CTRL` | RW | Read/Write RBR 활성화 |
| `0x34` | `RBR_R_BYTES` | RW | Read Monitor threshold, byte 단위 |
| `0x38` | `RBR_W_BYTES` | RW | Write Monitor threshold, byte 단위 |
| `0x3C` | `RBR_R_NOM` | RW | Read window의 nominal cycle 수 |
| `0x40` | `RBR_W_NOM` | RW | Write window의 nominal cycle 수 |
| `0x44` | `STALL_AR` | RO | `ARVALID && !ARREADY`인 cycle 수 |
| `0x48` | `STALL_R` | RO | `RVALID && !RREADY`인 cycle 수 |
| `0x4C` | `STALL_AW` | RO | `AWVALID && !AWREADY`인 cycle 수 |
| `0x50` | `STALL_W` | RO | `WVALID && !WREADY`인 cycle 수 |
| `0x54` | `STALL_B` | RO | `BVALID && !BREADY`인 cycle 수 |
| `0x58` | `READ_TXNS` | RO | 수락된 AR 요청 수 |
| `0x5C` | `WRITE_TXNS` | RO | 수락된 AW 요청 수 |
| `0x60` | `R_WAIT_CYCLES` | RO | Read Regulator의 WAIT cycle 수 |
| `0x64` | `W_WAIT_CYCLES` | RO | Write Regulator의 WAIT cycle 수 |
| `0x68` | `R_WINDOWS` | RO | 완료된 Read Monitor window 수 |
| `0x6C` | `W_WINDOWS` | RO | 완료된 Write Monitor window 수 |
| `0x70` | `ADAPT_CTRL` | RW | Adaptive 활성화·재시작·현재 단계·설정 유효성 |
| `0x74` | `LAT_SAMPLE` | RW | 최근 CPU latency sample, 쓰기 시 sample 전달 |
| `0x78` | `LAT_LIMITS` | RW | CPU latency 하한·상한 |
| `0x7C` | `ADAPT_POLICY` | RW | Hold·연속 확인 횟수·초기 단계 |

### `CTRL` (`0x00`)

| Bit | 이름 |
|---:|---|
| 0 | `START` |
| 1 | `SOFT_RESET` |
| 31:2 | reserved |

`START`와 `SOFT_RESET`은 idle 상태에서만 수락되는 1-cycle pulse입니다.

### `STATUS` (`0x04`)

| Bit | 이름 |
|---:|---|
| 0 | `BUSY` |
| 1 | `DONE` |
| 2 | `ERROR` |
| 31:3 | reserved |

### `TRANSFER_BYTES` (`0x10`)

32-bit 값 전체가 DMA command 한 번에 복사할 byte 수입니다.
0보다 큰 8의 배수로 설정합니다.

## Runtime 제어 레지스터

### `DMA_CFG` (`0x28`)

| Bits | 필드 | 설정값 |
|---:|---|---|
| 7:0 | `BURST_BEATS` | 1, 2, 4, 8, 16 |
| 9:8 | `RD_OUT_LIMIT` | `00`=1, `01`=2, `10`=4 |
| 11:10 | `WR_OUT_LIMIT` | `00`=1, `01`=2, `10`=4 |

Reset 값은 burst 16, Read/Write outstanding 4입니다.
지원 범위 밖의 burst 값은 16으로, outstanding `11`은 4로 처리합니다.
변경값은 다음 AR/AW 요청부터 적용하며, 이미 READY를 기다리는 요청은 기존 값을 유지합니다.

### `RBR_CFG` (`0x2C`)

| Bits | 필드 | 설명 |
|---:|---|---|
| 15:0 | `R_DELTA_Q8` | Read RBR delta, unsigned Q8.8 형식 |
| 31:16 | `W_DELTA_Q8` | Write RBR delta, unsigned Q8.8 형식 |

```text
delta = DELTA_Q8 / 256
THR%  = 100 / (1 + delta)
```

Reset 값은 0입니다. 설정 예시는 `0`=100%, `128`=66.7%, `256`=50%, `768`=25%입니다.

### `RBR_CTRL` (`0x30`)

| Bits | 필드 | 설명 |
|---:|---|---|
| 0 | `R_ENABLE` | `1`: Read RBR 활성화, `0`: bypass |
| 1 | `W_ENABLE` | `1`: Write RBR 활성화, `0`: bypass |
| 31:2 | reserved | 읽기 시 0 반환 |

Reset 값은 0입니다. 비활성화 시 해당 채널의 진행 중인 window와 WAIT를 초기화합니다.
Enable은 DMA idle 상태에서 변경합니다.

### Threshold와 nominal (`0x34`~`0x40`)

- `RBR_R_BYTES`, `RBR_W_BYTES`: threshold, 8 bytes 이상. 기본값 256 bytes.
- `RBR_R_NOM`, `RBR_W_NOM`: nominal cycle, 1~65535. 기본값 32 cycles.
- 허용 범위 밖의 값은 해당 채널을 bypass로 동작시킵니다.
- Threshold와 nominal은 DMA idle 상태에서 변경합니다.
- 유효한 threshold·nominal·delta 변경값은 각 채널의 다음 window 시작에 적용됩니다.
  RBR window는 DMA command가 바뀌어도 이어집니다.

## Adaptive 제어 레지스터

`LAT_SAMPLE`과 `LAT_LIMITS`의 단위는 `cycles/access × 100`입니다.
예: `106.36 cycles/access` → `10636`.

### `ADAPT_CTRL` (`0x70`)

| Bits | 접근 | 필드 | 설명 |
|---:|---|---|---|
| 0 | RW | `ENABLE` | `1`: Adaptive preset을 DMA/RBR 설정에 적용 |
| 2:1 | RO | `LEVEL` | 현재 단계, `L0`~`L3` |
| 3 | RO | `CONFIG_VALID` | 상한·하한 및 연속 확인 횟수의 유효성 |
| 8 | WO | `RESTART` | `INITIAL_LEVEL`을 다시 적용하는 1-cycle pulse |
| 31:9, 7:4 | - | reserved | 읽기 시 0 반환 |

### `LAT_SAMPLE` (`0x74`)

최근 32-bit sample을 저장합니다. `WSTRB != 0`인 쓰기마다 sample 전달 pulse가 발생합니다.
Sample 갱신에는 full-word write를 사용합니다.

### `LAT_LIMITS` (`0x78`)

| Bits | 필드 |
|---:|---|
| 15:0 | `LOW_LIMIT` |
| 31:16 | `HIGH_LIMIT` |

설정 유효 조건은 `LOW_LIMIT < HIGH_LIMIT`, `LOW_CONFIRM != 0`, `HIGH_CONFIRM != 0`입니다.
Adaptive 활성 상태에서 조건을 벗어나면 `L0`를 적용합니다.

### `ADAPT_POLICY` (`0x7C`)

| Bits | 필드 | 설명 |
|---:|---|---|
| 7:0 | `HOLD_SAMPLES` | 단계 변경 후 현재 단계를 유지할 유효 sample 수 |
| 15:8 | `LOW_CONFIRM` | 단계 상승에 필요한 하한 미만의 연속 sample 수 |
| 23:16 | `HIGH_CONFIRM` | 단계 하강에 필요한 상한 초과의 연속 sample 수 |
| 25:24 | `INITIAL_LEVEL` | 비활성화 또는 restart 시 적용할 단계 |
| 31:26 | reserved | 예약 영역 |

두 한계값 사이의 sample은 양쪽 연속 확인 횟수를 초기화합니다.
Hold는 전달받은 sample 수로 계산하며, hold 종료 후 연속 확인을 다시 시작합니다.

### Adaptive 활성 시 적용값

`ENABLE=1`이면 `DMA_CFG`와 RBR 설정 레지스터보다 다음 값이 우선 적용됩니다.

공통값은 burst 16, Read/Write outstanding 4, 양쪽 RBR 활성화,
threshold 256 bytes, nominal 32 cycles입니다.

| 단계 | Read/Write 목표 비율 | Read/Write delta Q8.8 |
|---:|---:|---:|
| `L0` | 50% | `256` |
| `L1` | 66.7% | `128` |
| `L2` | 80% | `64` |
| `L3` | 100% | `0` |

## Counter 집계 규칙

- DMA command 시작 시 0으로 초기화합니다.
- `CYC_TOTAL`, `CYC_READ`, `CYC_WRITE`는 각각 DMA 전체·RDMA·WDMA의 busy cycle을 셉니다.
- `READ_BEATS`, `WRITE_BEATS`는 실제 데이터 handshake를 셉니다.
- `0x44`~`0x6C`는 `STATUS.BUSY=1` 동안 집계하며 `0xFFFF_FFFF`에서 포화됩니다.
  Cycle·beat counter는 32-bit 누적값입니다.
- Stall은 외부 AXI 기준입니다. Read WAIT는 `STALL_R`과 `R_WAIT_CYCLES`에 중복 집계될 수 있습니다.
  Write RBR의 대기는 `W_WAIT_CYCLES`에서 확인합니다.
