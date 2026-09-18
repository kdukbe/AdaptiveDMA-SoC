# AdaptiveDMA-SoC

Arty Z7-20에서 CPU의 DDR access latency를 측정하고, 그 값에 따라 DMA의 목표 bandwidth 비율을 자동 조절하는 AXI4 DMA입니다. CPU latency와 DMA throughput 사이의 trade-off를 설계·검증하고 보드에서 측정했습니다.

## 주요 기능

- 64-bit AXI4 DMA, 4 KiB boundary 분할, runtime burst·outstanding 설정
- 데이터 경로: DDR → Read RBR → RDMA → FIFO → WDMA → Write RBR → DDR
- Read/Write Monitor와 Throttler를 결합한 RBR
- CPU0의 latency feedback, CPU1의 동적 DDR 부하
- RBR 목표 비율 50 / 66.7 / 80 / 100%, hysteresis·confirmation·hold 적용

RBR 비율은 nominal bandwidth를 기준으로 계산한 DMA 전송 목표입니다.

## 보드 결과

최종 7개 mode 비교에서 CPU1 부하를 OFF/ON으로 바꾸며 총 2,100개 sample을 측정했습니다.

| 설정 | DMA throughput | CPU latency 상한 위반률 |
|---|---:|---:|
| Fixed maximum | 689.69 MiB/s | 100.00% |
| Fixed RBR 50% | 381.46 MiB/s | 0.00% |
| Adaptive RBR | 426.12 MiB/s | 5.67% |

Adaptive RBR는 Fixed RBR 50% 대비 DMA throughput을 11.71% 높였으며, CPU latency 상한 위반률은 5.67%였습니다. [최종 결과](results/final/result.md)에 조건과 원본 로그를 정리했습니다.

100 MHz에서 post-route WNS +0.047 ns를 확보했습니다. 전체 PL 사용량은 LUT 2,646 / FF 2,388 / DSP 2 / BRAM 0입니다. [구현 결과](docs/implementation/result.md)

## 폴더 구성

```text
HW/
  rtl/          최종 RTL
  xsa/          bitstream 포함 최종 XSA
SW/
  cpu0/         DMA 제어·CPU latency 측정
  cpu1/         동적 DDR 부하·linker script
  shared.h      CPU0/CPU1 공유 제어 정보
sim/
  system/       최종 통합 TB·공통 SV 파일·검증 로그
  adaptive/     Adaptive 정책 단독 검증
  monitor/      Monitor 단독 검증
  throttler/    Throttler 단독 검증
  regulator/    Regulator 단독 검증
  counters/     분석 counter 단독 검증
results/
  sweep/        25개 설정 Sweep 결과
  final/        최종 7개 mode 보드 결과
  burst/        Burst Adaptive와 Adaptive RBR 비교
docs/
  implementation/  PPA·Block Design
  *.md, *.pdf  규격·레지스터 맵·보고서
README.md
```

## 보드 실행

대상은 Arty Z7-20 (`xc7z020clg400-1`), 도구는 Vivado/Vitis 2022.2입니다. `HW/xsa/adaptive_dma.xsa`에 bitstream이 포함되어 있습니다.

1. XSA로 플랫폼을 만들고 `ps7_cortexa9_0`, `ps7_cortexa9_1`용 standalone domain과 앱을 각각 만듭니다.
2. CPU0 앱 `src`에 `SW/cpu0/main.c`, `SW/shared.h`를 복사합니다.
3. CPU1 앱 `src`에 `SW/cpu1/load.c`, `SW/cpu1/lscript.ld`, `SW/shared.h`를 복사합니다.
4. CPU1 linker script는 제공된 `lscript.ld`를 사용합니다. 코드 영역을 `0x18000000`부터 배치해 CPU0와 분리합니다.
5. 두 앱을 `-O2`로 빌드합니다.
6. System Project의 실행 설정에 두 앱을 포함하고 전체 실행합니다. FPGA 프로그래밍·PS 초기화 후 CPU0와 CPU1이 함께 실행되도록 설정합니다.
7. CPU0 UART 출력 전체를 저장하고 아래의 PASS 메시지를 확인합니다.

CPU1은 UART 출력 없이 부하를 생성합니다. CPU0는 CPU1 준비를 최대 30초 기다린 뒤 실험을 시작하며, 실험 종료 시 CPU1의 부하 생성을 중지시킵니다. CPU1은 이후 대기 상태를 유지합니다.

```text
PASS: final adaptive benchmark complete, sink=<value>
```

하드웨어를 재구성할 때는 `HW/rtl`의 IP top `wrapper`를 Zynq PS 및 AXI interconnect와 연결합니다. 보드 구성 이미지는 `docs/implementation`에 있습니다.

## 시뮬레이션

Design Sources에 `HW/rtl/*.v`를 추가합니다. 통합 검증의 Simulation Sources는 아래 순서입니다.

1. `sim/system/dma_if.sv`
2. `sim/system/dma_pkg.sv`
3. `sim/system/axi_mem.sv`
4. `sim/system/tb_dma_rbr.sv` 또는 `sim/system/tb_adaptive_dma.sv`

선택한 TB 모듈을 Simulation top으로 설정하고 XSim에서 `run all`로 실행합니다.

- `tb_dma_rbr`: 고정 설정·bypass·runtime 설정·data integrity 등 35개 test의 regression
- `tb_adaptive_dma`: 전송 중 단계 변화·RBR 설정·AXI backpressure·4 KiB boundary·data 비교

단독 검증은 `HW/rtl`과 해당 폴더의 TB를 추가하고 `tb_adaptive`, `tb_monitor`, `tb_throttler`, `tb_regulator`, `tb_counters` 중 하나를 top으로 선택합니다. 공통 SV 파일은 통합 TB 실행에 필요하고, 단독 TB는 각 핵심 기능의 경계조건을 확인합니다.

## 문서와 측정 근거

- [프로젝트 보고서](docs/PROJECT_REPORT.pdf)
- [규격](docs/SPEC.md) · [레지스터 맵](docs/REGISTER_MAP.md)
- [25개 설정 Sweep](results/sweep/result.md)
- [최종 7개 mode 결과](results/final/result.md) · [Burst Adaptive 비교 결과](results/burst/result.md)
- [Implementation 결과와 PPA](docs/implementation/result.md)

각 결과 폴더의 `raw.log`는 보드 원본 출력입니다. Python 3로 해당 폴더의 `analyze.py`를 실행하면 CSV와 그래프를 생성합니다.

## 참고 논문

G. Valente et al., “Fine-Grained QoS Control via Tightly-Coupled Bandwidth Monitoring and Regulation for FPGA-Based Heterogeneous SoCs,” *IEEE TPDS*, 2025. [DOI 10.1109/TPDS.2024.3513416](https://doi.org/10.1109/TPDS.2024.3513416)
