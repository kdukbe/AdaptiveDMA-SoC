# Burst Adaptive와 RBR Adaptive 보드 비교

Burst 길이를 조절하는 방식과 RBR 비율을 조절하는 방식을 비교한 추가 실험입니다.
같은 실행에서 Fixed maximum, Static burst 8, Fixed RBR 50%를 다시 측정해
두 Adaptive 방식의 비교 기준으로 사용했습니다.

## 실험 조건과 결과

Arty Z7-20에서 CPU1 부하를 `OFF → ON → OFF → ON`으로 바꾸며 세 번
반복했습니다. 두 Adaptive 방식은 같은 CPU latency limit, 판단 FSM,
hysteresis, confirmation, hold 및 8 MiB DMA 명령을 사용했습니다.

전체 실행은 다음 조건을 통과했습니다.

- 2,400개 CPU latency sample 확보
- 구간별 집계 32개와 모드별 집계 8개의 재계산 일치
- Burst Adaptive `27회`, RBR Adaptive `9회` 단계 전환 확인
- 모든 DMA beat/transaction 및 데이터 비교 통과
- CPU1 load generator 24개 구간 수행
- 최종 `PASS`

CPU latency 상한은 `150.94 cycles/access`입니다.

| 모드 | CPU 평균 | P95 | P99 | 상한 초과 수 | DMA MiB/s |
|---|---:|---:|---:|---:|---:|
| Fixed maximum | 229.80 | 241.86 | 242.13 | 300/300 (100%) | 681.52 |
| Static burst 8 | 150.09 | 158.62 | 158.67 | 150/300 (50%) | 560.15 |
| Fixed RBR 50% | 132.46 | 139.82 | 140.42 | 0/300 (0%) | 381.46 |
| Burst Adaptive | 140.78 | 158.42 | 158.67 | 66/300 (22%) | 499.98 |
| RBR Adaptive | 139.55 | 149.60 | 162.21 | 12/300 (4%) | 439.47 |

## 주요 결과

RBR Adaptive는 Burst Adaptive와 비교해:

- 상한 위반을 `66회 → 12회`, 즉 `81.8%` 감소
- 위반률을 `22% → 4%`, 즉 `18%p` 감소
- 평균 latency를 `140.78 → 139.55 cycles/access`로 감소
- P95를 `158.42 → 149.60 cycles/access`로 감소하여 상한 아래로 진입
- 대신 DMA 처리량은 `499.98 → 439.47 MiB/s`, 즉 `12.1%` 감소

RBR Adaptive는 DMA 처리량이 줄어드는 대신 CPU latency의 P95와 상한 초과율이 낮았습니다.

또한 RBR Adaptive는 위반이 전혀 없는 고정 RBR 50%보다 DMA 처리량을
`381.46 → 439.47 MiB/s`, 즉 `15.2%` 높였습니다. 고정된 보수 설정보다
대역폭을 회복하면서 P95 제한을 만족한 것이 Adaptive 제어의 이점입니다.

## 단계 전환과 지연 특성

- Burst Adaptive: `L1 90회`, `L2 210회`; 부하 중에도 비교적 공격적인
  burst를 사용해 처리량은 높지만 위반이 반복되었습니다.
- RBR Adaptive: `L0 160회`, `L1 140회`; CPU1 부하에서 L0로 내려가
  위반을 빠르게 줄였습니다.
- RBR Adaptive에서는 일부 sample의 latency가 크게 상승해
  P99와 최댓값이 Burst Adaptive보다 높았습니다.

## 결과 자료

- `raw.log`: 원본 UART 출력
- `summary.csv`: 2,400개 sample에서 독립 재계산한 결과
- `trace.svg`: RBR Adaptive의 latency와 단계 변화
- `burst_trace.svg`: Burst Adaptive의 latency와 단계 변화
- `tradeoff.svg`: 위반률과 DMA 처리량 비교
- `analyze.py`: Sample 수, 집계값, 처리량과 단계 전환을 재계산하는 검증 코드
