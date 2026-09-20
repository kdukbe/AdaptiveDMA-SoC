# AdaptiveDMA-SoC 규격

## 플랫폼

| 항목 | 설정 |
|---|---|
| 보드 | Digilent Arty Z7-20 |
| SoC | Zynq-7000 XC7Z020 |
| PL clock | 100 MHz |
| 제어 Interface | AXI4-Lite, 32-bit |
| 데이터 Interface | AXI4 memory-mapped, 64-bit |
| Reset | active-low `RSTN` |
| 소프트웨어 | Vitis bare-metal |

## 데이터 경로

```text
DDR -> Read RBR -> RDMA -> 64-bit FIFO -> WDMA -> Write RBR -> DDR
```

| 모듈 | 역할 |
|---|---|
| `controller.v` | 레지스터 접근, command 및 상태 관리 |
| `adaptive.v` | CPU latency 기반 hysteresis와 실측 preset 선택 |
| `rdma.v` | AXI Read 전송 |
| `wdma.v` | AXI Write 전송 |
| `dma_engine.v` | DMA start/done/error 제어 |
| `FIFO.v` | Stream buffering과 backpressure 처리 |
| `monitor.v` | Threshold bytes 전송에 걸린 cycle 측정 |
| `throttler.v` | 논문 식에 따른 idle cycle 계산 |
| `regulator.v` | Monitor·Throttler 결합 및 AXI 규약을 지키는 VALID/READY gate |
| `counters.v` | DMA command별 AXI·RBR 통계 집계 |
| `top.v` | 내부 모듈 연결 |
| `wrapper.v` | Vivado 연결용 AXI 포트 |

## RTL 동작 규격

| 항목 | 동작 |
|---|---|
| Read burst | Runtime 1/2/4/8/16-beat `INCR` 설정 |
| Write burst | Runtime 1/2/4/8/16-beat `INCR` 설정 |
| Beat size | 8 bytes |
| Read outstanding | Runtime 1/2/4 설정 |
| Write outstanding | Runtime 1/2/4 설정, AW 수락부터 B 응답 수락까지 집계 |
| FIFO | 64-bit, depth 64 |
| Alignment | Source·destination 주소를 8-byte 단위로 정렬 |
| Transfer length | 0보다 큰 8 bytes의 배수 |
| 4 KiB boundary | 경계를 넘기 전에 burst 분할 |
| AXI ID | 0 고정 |
| Read response | `RRESP=OKAY`를 전제로 동작 |
| Write response | `BRESP`가 OKAY 이외의 값이면 error 설정 |
| RBR threshold | Read/Write별 runtime 설정, reset 기본값 256 bytes |
| RBR nominal time | Read/Write별 runtime 설정, reset 기본값 32 cycles |
| RBR control | Read/Write별 독립 enable 및 unsigned Q8.8 delta |
| 통계 | Command별 AXI stall·transaction, RBR WAIT·window 집계 |
| Adaptive feedback | 소프트웨어가 CPU cycles/access × 100 형식의 sample 전달 |
| Adaptive level | 실측한 RBR preset 4개, `L0`~`L3` |


## RBR 동작

Read와 Write 데이터 채널을 독립적으로 제어합니다. AR·AW·B 채널은 기존 handshake로 동작합니다.
목표 비율 `THR%`, 기준 전송 시간 `nomcc`, 실제 측정 시간 `copycc`로 WAIT 시간 `idlecc`를 계산합니다.

```text
delta  = (100 - THR%) / THR%
idlecc = max(nomcc + delta * nomcc - copycc, 0)
```

- **측정**: Threshold bytes를 채우는 구간을 window로 정의하며, 첫 handshake부터 마지막 handshake까지 셉니다.
  Read는 beat당 8 bytes, Write는 활성 `WSTRB` bit 수만큼 집계합니다.
- **Command 경계**: 미완료 window는 다음 command까지 이어지며, 그 사이의 idle 시간도 측정에 포함합니다.
- **설정 반영**: 유효한 threshold·nominal·delta 변경은 각 채널의 다음 window 시작 시 적용합니다.
- **Enable**: 채널별 독립 설정이며 reset 시 OFF입니다. OFF 전환 시 측정·WAIT를 초기화하고 bypass합니다.
  소프트웨어는 DMA가 idle일 때 enable을 변경합니다.
- **지원 범위**: Threshold는 8 bytes 이상, nominal은 1~65,535 cycles입니다. 범위를 벗어나면 해당 채널은 bypass합니다.

## Adaptive 동작

실측한 DMA 설정을 traffic 부하가 낮은 순서대로 배치합니다. CPU latency sample이
상한을 연속으로 초과하면 DMA 전송을 줄이는 단계로, 하한보다 연속으로 낮으면 전송을
늘리는 단계로 이동합니다. Hysteresis 구간의 sample은 양쪽 연속 횟수를 초기화합니다.
단계 변경 후에는 sample 수로 정한 hold 구간을 두어 즉시 반대 방향으로 전환되는 것을
방지합니다.

RBR preset은 `RBR50_T256`, `RBR67_T256`, `RBR80_T256`, `RBR100_T256`입니다.
Burst 16과 outstanding 4를 유지하며 RBR 목표 비율을 자동 조절합니다. 25개 설정 Sweep으로
동작점별 특성을 측정했으며, 같은 레지스터를 통한 소프트웨어 고정 설정도 지원합니다.
