# FPGA Speech and Spectrum Analyzer (Altera DE2)

This repository hosts the Verilog HDL source code and supporting documentation for a digital signal processing (DSP) project implemented on the **Altera DE2** development board. The system functions as a dual-mode spectrum and I/Q analyzer, processing real-time audio input and visualizing the results via a VGA interface.

---

## Project Overview and Objectives

The primary goal of this project is to integrate various hardware and software components to perform sophisticated signal analysis in a controlled laboratory environment.

* **Real-time Acquisition:** Interface with an external microphone/line-in for continuous audio sampling.
* **Signal Processing:** Execute a Fast Fourier Transform (FFT) on the acquired data.
* **Visual Output:** Drive a VGA display to render analysis results graphically.
* **Dual-Mode Operation:** Provide two distinct modes of analysis (Full Spectrum and Selective I/Q).

---

## Technical Specifications

### 1. Hardware Platform
* **FPGA Board:** Altera DE2
* **Design Language:** Verilog HDL

### 2. Fast Fourier Transform (FFT) Parameters
| Parameter | Value | Notes |
| :--- | :--- | :--- |
| **Sampling Frequency ($\mathbf{f_s}$)** | $25 \text{ kHz}$ | Set for speech analysis and efficient hardware implementation. |
| **Number of Points ($\mathbf{N}$)** | $512$ | A power-of-two size suitable for the FFT algorithm. |
| **Frequency Resolution ($\mathbf{\Delta f}$)** | $\approx 48.83 \text{ Hz}$ | Calculated as $f_s / N$. |

### 3. I/O Interfaces
* **Input:** Audio interface (Microphone/Line-in)
* **Output:** Standard VGA Connector

---

## Operating Modes

The system operates in one of two modes, toggled by a physical **SWITCH** on the DE2 board.

### Mode 1: Full Spectrum Analyzer (Default)

This mode provides a high-level view of the input signal's frequency content.

* **Function:** Displays the magnitude spectrum of the 512-point FFT output.
* **Control:** Runs continuously on the acquired audio data.
* **VGA Output:** Graph of **Magnitude** vs. **Frequency**.

### Mode 2: Selective I/Q Analysis

This mode allows users to zoom in on a specific frequency component for detailed phase and amplitude analysis.

* **Activation:** Toggled via a dedicated DE2 SWITCH.
* **Frequency Selection:** The frequency of interest is selected by the user using the **KEYs** (pushbuttons) on the DE2 board.
* **Function:** Extracts the In-phase ($\mathbf{I}$) and Quadrature ($\mathbf{Q}$) components for the selected frequency, providing highly precise phase and amplitude data.
* **VGA Output:** Visualization of the **I/Q components** (e.g., as a constellation plot or time-domain graph).
