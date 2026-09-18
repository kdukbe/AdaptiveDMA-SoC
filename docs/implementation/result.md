# 최종 Implementation 결과

## 결과 요약

- 대상: Arty Z7-20, `xc7z020clg400-1`
- 도구: Vivado 2022.2
- PL clock: 100 MHz (`10.000 ns`)
- Implementation: 전체 routing 완료, routing 오류 0개
- Setup: WNS `+0.047 ns`, TNS `0.000 ns`, 위반 endpoint 0개
- Hold: WHS `+0.030 ns`, THS `0.000 ns`, 위반 endpoint 0개
- Timing 검사: 제약이 없는 내부 endpoint 0개, I/O delay 누락 0개
- Bitstream·XSA 생성: PASS

최종 설계는 목표 clock 100 MHz의 timing을 만족합니다.

## 전체 PL 자원 사용량

아래 값은 직접 설계한 DMA IP와 Vivado가 생성한 AXI 연결 회로를 포함하는 전체 PL의
post-place 자원 사용량입니다.

| 자원 | 사용량 | 가용량 | 사용률 |
|---|---:|---:|---:|
| Slice LUT | 2,646 | 53,200 | 4.97% |
| LUT as logic | 2,480 | 53,200 | 4.66% |
| LUT as memory | 166 | 17,400 | 0.95% |
| Slice register | 2,388 | 106,400 | 2.24% |
| Slice | 1,013 | 13,300 | 7.62% |
| BRAM tile | 0 | 140 | 0.00% |
| DSP | 2 | 220 | 0.91% |
| BUFG | 1 | 32 | 3.13% |

## DMA IP 합성 결과

`wrapper_0`의 Out-of-Context 합성 결과는 LUT 2,045개, register 1,558개,
BRAM tile 0개, DSP 2개입니다. 이 값은 DMA IP 단독 기준이며, 위 표는 전체 PL의
post-place 기준입니다.

## Critical Path

가장 작은 setup slack을 갖는 경로는 Controller의 Adaptive enable 레지스터에서 시작해
Write Throttler의 `target_cycles[26]` 레지스터에 도달합니다.

```text
Controller의 adapt_enable 레지스터
  -> Write Throttler의 Q8.8 곱셈 (DSP48E1)
  -> 32-bit target cycle 덧셈·carry chain
  -> target_cycles 레지스터
```

- Data path delay: `9.814 ns`
- Logic / routing delay: `6.546 ns / 3.268 ns`
- Logic 단계 수: 13 (`1 DSP48E1`, `9 CARRY4`, `3 LUT2`)
- Slack: 100 MHz에서 `+0.047 ns`

RBR target cycle 계산의 곱셈·덧셈 조합 경로가 timing을 제한합니다. 목표 clock을
높이는 경우 이 경로의 pipeline 적용과 변경된 제어 latency의 재검증을 검토할 수 있습니다.

## 전력 추정

Vivado의 total on-chip power 추정값은 `1.414 W`이며, dynamic power `1.280 W`,
device static power `0.135 W`입니다. Junction temperature 추정값은 `41.3 °C`입니다.
Vectorless switching 가정을 사용한 분석으로 confidence는 Medium입니다.
Dynamic power 추정값 중 `wrapper_0` 계층은 `0.014 W`, Processing System은
`1.258 W`를 차지합니다.

전력과 온도 수치의 출처는 Vivado 추정 결과입니다.

## 경고 내역

기본 routed DRC 결과는 오류 0개, 경고 12개입니다.

- Read/Write Throttler 곱셈기의 DSP pipeline 권고 8개
- Vivado가 생성한 AXI interconnect의 LUT equation 경고 3개
- Vivado가 생성한 AXI interconnect의 unused-routing 경고 1개

Methodology report에는 Xilinx가 생성한 AXI interconnect 내부의 asynchronous reset
경고 3개가 추가로 있습니다. Routing 대상 net 4,687개는 모두 연결되었습니다.

## 설계 자료

Vivado Block Design은 [block_design.png](block_design.png)에 저장했습니다.
해당 bitstream이 포함된 하드웨어 플랫폼은 [adaptive_dma.xsa](../../HW/xsa/adaptive_dma.xsa)입니다.

## 보드 검증 자료

CPU0·CPU1을 함께 실행한 최종 보드 실험과 원본 로그 분석을 완료했습니다.
측정 조건과 비교 결과는 [최종 보드 결과](../../results/final/result.md)에 정리했습니다.
