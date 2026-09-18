# Parameter Sweep 결과

최종 Adaptive RBR 설정을 선택하기 위해 DMA 처리량과 CPU latency의 관계를 측정했습니다.

## 실험 조건

- 보드: Arty Z7-20
- DMA clock: 100 MHz
- 전송량: 실행당 8 MiB
- CPU 측정 방식: 1 MiB Normal Non-cacheable buffer의 dependent pointer chase
- CPU 접근 수: 측정 1회당 16,384회
- 설정 수: 25개
- 반복 수: 설정당 100회
- 전체 DMA 실행 수: 2,500회
- Latency 상한: 각 설정과 함께 측정한 CPU-only 평균의 150%

Sample 하나는 DDR에 16,384회 접근한 평균 latency입니다.
설정마다 얻은 sample 100개로 `P95`와 `P99`를 계산했습니다.

## 측정값과 데이터 검증

- 전체 2,500개 sample을 확보했습니다.
- 각 CPU 시간 측정 구간 전체에서 DMA 전송이 진행 중임을 확인했습니다.
- Hardware counter와 일부 위치의 데이터 비교가 모두 통과했습니다.
- 각 설정의 마지막 8 MiB 전체 데이터 비교가 통과했습니다.
- 25개 설정 모두 오류 0개를 기록했습니다.
- 함께 측정한 CPU-only 평균은 106.34~106.39 cycles/access였습니다.
- 평균·P95·P99·DMA cycle·처리량을 재계산한 결과가 UART 출력 정밀도 범위에서 일치했습니다.

Slowdown은 각 설정과 함께 측정한 CPU-only baseline으로 계산했습니다.

## 주요 결과

| 설정 | CPU 평균 | P99 | Slowdown | 상한 초과율 | DMA 처리량 |
|---|---:|---:|---:|---:|---:|
| `RAW_B16_O4` | 208.34 cycles | 209.18 | 95.89% | 100% | 734.24 MiB/s |
| `RBR80_T256` | 151.15 cycles | 151.49 | 42.12% | 0% | 608.87 MiB/s |
| `RAW_B8_O4` | 143.34 cycles | 143.63 | 34.75% | 0% | 586.40 MiB/s |
| `RBR50_W_ONLY` | 123.97 cycles | 128.13 | 16.55% | 0% | 381.47 MiB/s |
| `RBR50_T256` | 128.33 cycles | 133.91 | 20.65% | 0% | 381.47 MiB/s |
| `RAW_B2_O4` | 115.21 cycles | 115.46 | 8.29% | 0% | 195.70 MiB/s |

최대 DMA 설정의 처리량은 64-bit/100 MHz 기준 이론적 복사 처리량의 96.24%에 도달했습니다.
CPU 평균 latency는 약 두 배가 되었고, 100회 모두 Sweep 상한을 초과했습니다.

`RBR80_T256`은 상한 초과 0회를 기록한 설정 중 처리량이 가장 높았으며,
P99는 상한보다 8.05 cycles 낮았습니다. `RAW_B8_O4`는 처리량이 22.47 MiB/s 낮은 대신
CPU latency 여유가 더 컸습니다. 이 부하에서 상한을 만족한 RBR bypass 설정 중
처리량이 가장 높아 고정 Burst 비교군으로 선택했습니다.

## Burst와 Outstanding의 영향

Burst와 outstanding을 높이면 DMA 처리량이 증가하지만 CPU latency의 증가 폭도 달라집니다.
Burst 16에서 outstanding을 1, 2, 4로 바꾼 결과는 다음과 같습니다.

| Outstanding | CPU slowdown | DMA 처리량 |
|---:|---:|---:|
| 1 | 12.93% | 238.25 MiB/s |
| 2 | 25.86% | 487.12 MiB/s |
| 4 | 95.89% | 734.24 MiB/s |

Outstanding 2에서 4로 높이면 처리량은 50.7% 증가하고 CPU slowdown은 약 70%p 증가했습니다.
최대 설정을 계속 유지할 때 CPU 지연이 크게 늘어나는 구간으로,
CPU latency에 따라 DMA 전송량을 조절할 필요성을 보여줍니다.

Burst 1, outstanding 2와 4에서는 `STALL_AR`·`STALL_AW`가 각각 약 52.4만, 78.1만 cycle
누적되었습니다. 짧은 transaction을 자주 발행하면서 outstanding 상한에 도달하는 동작입니다.
RBR bypass 설정의 R-channel stall은 거의 없었으며, 처리량은 주로 transaction 효율과
동시 요청 수의 영향을 받았습니다.

## RBR 목표 비율의 영향

Threshold를 256 bytes로 고정하고 Read/Write RBR을 모두 활성화했습니다.

| 목표 비율 | Delta Q8 | 이론 대역폭 대비 실측 비율 | CPU slowdown | P99 |
|---:|---:|---:|---:|---:|
| 100% | 0 | 96.24% | 95.91% | 209.29 |
| 80% | 64 | 79.81% | 42.12% | 151.49 |
| 66.7% | 128 | 66.66% | 28.58% | 150.31 |
| 50% | 256 | 50.00% | 20.65% | 133.91 |
| 33.3% | 512 | 33.33% | 13.04% | 122.97 |
| 25% | 768 | 25.00% | 10.29% | 120.80 |

25~80% 설정에서는 목표 비율에 가까운 처리량을 얻었습니다.
100% 설정에서는 DMA/DDR 경로의 전송 효율에 따라 이론 대역폭의 96.24%를 기록했습니다.
보드 측정에서 Monitor–Throttler 계산에 따른 대역폭 제한을 확인했습니다.

66.7%, 50%, 25% 설정은 RBR bypass 설정보다 반복 측정 간 변동이 컸습니다.
CPU 측정 구간과 주기적인 RBR PASS/WAIT 구간의 상대적 위치가 영향을 줄 수 있습니다.
이러한 변동을 고려해 hysteresis와 연속 sample 확인을 적용했습니다.

## Threshold와 제어 채널의 영향

목표 비율을 50%로 유지하면 threshold별 DMA 처리량은 약 381.47 MiB/s로 같았지만,
CPU latency는 차이가 있었습니다.

| Threshold | CPU 평균 | CPU 표준편차 | P99 |
|---:|---:|---:|---:|
| 256 bytes | 128.33 | 4.66 | 133.91 |
| 512 bytes | 131.59 | 5.40 | 139.53 |
| 1536 bytes | 137.99 | 1.08 | 139.78 |

측정한 세 조건 중 평균과 P99가 가장 낮은 256-byte window를 Adaptive 설정으로 선택했습니다.
큰 window에서는 제어 빈도가 낮아지고 연속 전송 구간이 길어집니다.
1536 bytes에서는 반복 간 표준편차가 작았지만 평균과 P99는 높았습니다.

같은 목표 비율 50%에서 제어 채널을 바꾼 결과는 다음과 같습니다.

| 활성 RBR 채널 | CPU 평균 | P99 | Read WAIT | Write WAIT |
|---|---:|---:|---:|---:|
| Read + Write | 128.33 | 133.91 | 1,048,561 | 1,048,560 |
| Read only | 127.95 | 133.90 | 1,048,561 | 0 |
| Write only | 123.97 | 128.13 | 0 | 1,048,560 |

Write-only 설정에서 CPU latency가 가장 낮았습니다. 이때 Read RBR은 bypass지만
외부 `STALL_R`은 약 1,048,414 cycle 발생했습니다. Write throttling으로 중간 FIFO가 차면
RDMA의 수신 준비 신호가 낮아져 DDR 읽기도 함께 제한됩니다.
Read/Write 양쪽 제어는 Write-only와 처리량이 같았고 CPU latency는 더 높았습니다.

## 최종 설정 선정

Burst 16과 outstanding 4는 최대 처리량을 확보하는 설정입니다.
Threshold 256 bytes는 목표 50%의 threshold 비교에서 평균과 P99가 가장 낮았습니다.
최종 Controller는 이 값을 고정하고 RBR 목표 비율을 변경합니다.

| 단계 | 설정 | CPU 평균 | P99 | DMA MiB/s |
|---:|---|---:|---:|---:|
| `L0` | `RBR50_T256` | 128.32 | 133.91 | 381.46 |
| `L1` | `RBR67_T256` | 136.76 | 150.31 | 508.61 |
| `L2` | `RBR80_T256` | 151.15 | 151.49 | 608.87 |
| `L3` | `RBR100_T256` | 208.34 | 209.29 | 734.22 |

네 단계를 전송 목표 비율 순으로 배치해 CPU latency에 따라 DMA 대역폭을 조절합니다.

## 결과 자료

- `raw.log`: 원본 UART 출력
- `summary.csv`: UART 집계값과 독립 재계산 지표
- `tradeoff.svg`: CPU slowdown과 DMA 처리량 비교 그래프
- `analyze.py`: 로그 분석, 측정값 검증 및 그래프 생성 코드
