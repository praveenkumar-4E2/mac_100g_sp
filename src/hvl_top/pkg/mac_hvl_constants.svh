/**
 * @brief HVL façade-owned protocol constants (mac_test_pkg member).
 *
 * Owns the UVM environment's RS/Ethernet constants. This file is a member of
 * mac_test_pkg (text-included), so it
 * must NOT declare `package`/`endpackage`. It is included at the head of the
 * package, before agent/transaction classes, so every RS/Ethernet protocol
 * constant has one façade-owned owner.
 *
 * IEEE 802.3 constants shared across the testbench agents/sequences. Beat
 * geometry is deliberately NOT defined here: the byte lanes per beat and bits
 * per beat come from the mac_rs_stream_if parameters (DATA_WIDTH, KEEP_WIDTH =
 * DATA_WIDTH/8) via the virtual interface handle, so agents track the actual
 * instance.
 */
`ifndef MAC_HVL_CONSTANTS_SVH
`define MAC_HVL_CONSTANTS_SVH

// Preamble (7 x 0x55) + SFD (0xD5), IEEE 802.3 Clause 3.2.1
localparam int RS_PREAMBLE_BYTES = 7;
localparam int RS_SFD_BYTES = 1;
localparam int RS_PREAMBLE_SFD_BYTES = RS_PREAMBLE_BYTES + RS_SFD_BYTES;  // 8

// Header: DA + SA + length/type (Clause 3.2.2)
localparam int RS_DA_BYTES = 6;
localparam int RS_SA_BYTES = 6;
localparam int RS_ET_BYTES = 2;
localparam int RS_HDR_BYTES = RS_DA_BYTES + RS_SA_BYTES + RS_ET_BYTES;  // 14

// Minimum frame without FCS (preamble + SFD + header)
localparam int RS_MIN_FRAME_BYTES = RS_PREAMBLE_SFD_BYTES + RS_HDR_BYTES;  // 22
localparam int RS_FCS_BYTES = 4;

// Implementation frame profiles. Frame octets count DA through FCS; payload
// octets exclude the 14-byte MAC header and FCS. The default agent profile
// remains IEEE basic Ethernet, while tests may select either larger profile.
localparam int MAC_STANDARD_FRAME_OCTETS = 1518;
localparam int MAC_JUMBO_FRAME_OCTETS = 9000;
localparam int MAC_SUPER_JUMBO_FRAME_OCTETS = 16384;
localparam int MAC_SUPER_JUMBO_PAYLOAD_BYTES =
    MAC_SUPER_JUMBO_FRAME_OCTETS - RS_HDR_BYTES - RS_FCS_BYTES;

// IEEE 802.3 Clause 3.2.7: length/type <= 1500 is a length field
localparam int RS_ETH_LEN_BOUND = 16'h0600;

// IEEE 802.3 Clause 4.2.3.2.3: minimum inter-packet gap (bit times)
localparam int RS_IPG_BITS_DEFAULT = 96;

// length_error injection: payload.size() - RS_LEN_ERR_OFFSET keeps the
// length/type field below the type threshold and mismatched with the
// counted payload, so rx_length_check's invalid_length condition
// (lt <= MAX_CLIENT_DATA) && (payload_count < lt) flags the frame.
localparam int RS_LEN_ERR_OFFSET = 3;

//========================================================================
// AXI4-Stream tuser sideband bit indexes (TX input / RX output).
// These are the bit positions within the AXI tuser bus that carry
// per-frame status. The tuser bus width comes from the virtual interface
// (typically 8 bits at DATA_WIDTH=512).
//========================================================================

// tuser[AXI_TUSER_ERROR_BIT] — asserted by the TX client to indicate
// an error/drop condition for the current frame; maps to mac_error.
localparam int AXI_TUSER_ERROR_BIT = 0;

// tuser[AXI_TUSER_FCS_PRESENT_BIT] — asserted by the TX client to
// indicate the last 4 bytes of the payload are a client-supplied FCS;
// maps to mac_fcs_present. On RX output this bit is reserved-zero
// because the wire FCS is always stripped before delivery.
localparam int AXI_TUSER_FCS_PRESENT_BIT = 1;

// Bounded wait defaults (W4): absolute simulation-time timeout for the
// reset/configuration-completion wait and for monitor/queue completion
// waits. Generous relative to the ~200ns normal bootstrap; a stalled DUT
// fails the test well within the bound.
localparam time MAC_CONFIG_DONE_TIMEOUT_NS = 1_000_000;  // 1 ms
// This project is compiled at 1 ps precision, so the timeout is expressed
// in those ticks: 10,000,000 ticks = 10 us. A 16,384 B frame alone spans
// 256 512-bit beats, so retain this bounded but practical allowance for
// both standard and large-frame tests.
localparam time MAC_COMPLETION_TIMEOUT_NS = 100_000_000;

`endif  // MAC_HVL_CONSTANTS_SVH
