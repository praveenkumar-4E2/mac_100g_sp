/**
 * @brief HVL façade-owned shared types (mac_test_pkg member).
 *
 * Typed enums used across the canonical frame, codecs, compare helpers,
 * reset/config completion, and checkers. This file is a member of
 * mac_test_pkg (text-included), so it must NOT declare
 * `package`/`endpackage`. It is dependency-free (no UVM import) and is
 * included with mac_hvl_constants.svh at the head of the package, so any
 * member may reference these types by name.
 *
 * Enum base types and values are explicit so the on-wire/stored encoding is
 * stable across elaboration and printing; there is no behavioral change from
 * adding these types - nothing consumes them until UTL-014 includes the file
 * and UTL-016/UTL-052 migrate consumers to them.
 */
`ifndef MAC_HVL_TYPES_SVH
`define MAC_HVL_TYPES_SVH

//========================================================================
// Frame source direction.
// Identifies which point in the MAC data path produced (or consumes) a
// canonical frame, so a codec/checker knows how to interpret the frame:
//  - AXI TX: client-side stream into the DUT TX path (no preamble/SFD).
//  - RS  TX: line-side stream out of the DUT TX path (preamble/SFD + FCS).
//  - RS  RX: line-side stream into the DUT RX path (preamble/SFD + FCS).
//  - AXI RX: client-side stream out of the DUT RX path (no preamble/SFD,
//            wire FCS stripped).
//========================================================================
typedef enum int {
  MAC_FRAME_DIR_AXI_TX = 0,
  MAC_FRAME_DIR_RS_TX  = 1,
  MAC_FRAME_DIR_RS_RX  = 2,
  MAC_FRAME_DIR_AXI_RX = 3
} mac_frame_dir_e;

// Physical endpoint roles, named from the DUT point of view.  This is an
// architectural name only: UVM_ACTIVE/UVM_PASSIVE still selects whether an
// agent owns pins, but never describes the data-path role.
typedef enum int {
  MAC_ENDPOINT_CLIENT_INGRESS = 0,
  MAC_ENDPOINT_CLIENT_EGRESS  = 1,
  MAC_ENDPOINT_LINE_INGRESS   = 2,
  MAC_ENDPOINT_LINE_EGRESS    = 3,
  MAC_ENDPOINT_APB            = 4,
  MAC_ENDPOINT_RESET          = 5
} mac_endpoint_role_e;

//========================================================================
// Reset / configuration-completion event.
// Describes the reset and boot handoff events that the reset agent and the
// top-level reset/configuration controller emit. MAC_RESET_EVENT_CONFIG_DONE
// is the typed replacement for the current wildcard `rst_done` database flag
// (published by mac_tb_top), which mac_wait_utils will wait on in W4.
//========================================================================
typedef enum int {
  MAC_RESET_EVENT_NONE        = 0,
  MAC_RESET_EVENT_ASSERT      = 1,
  MAC_RESET_EVENT_DEASSERT    = 2,
  MAC_RESET_EVENT_CONFIG_DONE = 3
} mac_reset_event_e;

//========================================================================
// Frame result.
// Outcome of a frame after DUT processing, as classified by monitors and
// used by the compare/scoreboard path. Aligned with the DUT RX status
// signals (rx_crc_error, rx_length_error, rx_alignment_error,
// rx_frame_drop) plus a clean outcome; MAC_FRAME_RESULT_DROPPED also covers
// frames dropped by the TX admission path.
//========================================================================
typedef enum int {
  MAC_FRAME_RESULT_CLEAN           = 0,
  MAC_FRAME_RESULT_CRC_ERROR       = 1,
  MAC_FRAME_RESULT_LENGTH_ERROR    = 2,
  MAC_FRAME_RESULT_ALIGNMENT_ERROR = 3,
  MAC_FRAME_RESULT_DROPPED         = 4
} mac_frame_result_e;

`endif  // MAC_HVL_TYPES_SVH
