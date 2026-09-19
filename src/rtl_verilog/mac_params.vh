`ifndef MAC_PARAMS_VH
`define MAC_PARAMS_VH
`define AXIS_DATA_WIDTH 512
`define AXIS_KEEP_WIDTH 64
`define MAC_ADDR_WIDTH 48
`define CRC_WIDTH 32
`define MAC_MIN_FRAME_OCTETS 64
`define MAC_HEADER_OCTETS 14
`define MAC_FCS_OCTETS 4
// Frame limits count DA through FCS; client payload excludes those 18 bytes.
// Jumbo and super-jumbo are implementation profiles, selected through the
// MAX_FRAME_SIZE register.  Storage is sized for the largest profile.
`define MAC_STANDARD_FRAME_OCTETS 1518
`define MAC_JUMBO_FRAME_OCTETS 9000
`define MAC_SUPER_JUMBO_FRAME_OCTETS 16384
`define MAC_SUPER_JUMBO_PAYLOAD_OCTETS (`MAC_SUPER_JUMBO_FRAME_OCTETS - `MAC_HEADER_OCTETS - `MAC_FCS_OCTETS)
`define MAC_TX_BUFFER_BYTES `MAC_SUPER_JUMBO_FRAME_OCTETS
`define MAC_RX_BUFFER_BYTES `MAC_SUPER_JUMBO_FRAME_OCTETS
`endif
