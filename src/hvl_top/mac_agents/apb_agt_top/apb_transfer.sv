/**
 * @brief APB transfer status enumeration.
 *
 * Describes the outcome of one APB transfer as reported by the driver
 * response or observed by the monitor. It is deliberately independent of
 * any MAC register-map import or address policy: a generic APB agent must
 * be able to carry unaligned/invalid accesses for PSLVERR verification.
 */
typedef enum bit [2:0] {
  APB_OK,
  APB_SLVERR,
  APB_TIMEOUT,
  APB_RESET_ABORT,
  APB_PROTOCOL_ERROR
} apb_transfer_status_e;

/**
 * @brief Reusable APB transfer sequence item.
 *
 * Represents exactly one APB transfer (never a multi-transfer command):
 * request fields (direction/address/write data), completion response fields
 * (read data/slave error/status), and observation metadata (phase timing,
 * wait cycles, ordinal, source ID, tag). The expected-error intent
 * (expect_slverr) is kept distinct from the observed slverr/status so a
 * negative-address test cannot disguise a DUT result.
 *
 * Widths are parameters defaulting to the current apb_if binding
 * (16-bit address, 32-bit data); the agent config derives and validates the
 * same widths from the bound virtual interface.
 */
class apb_transfer_c #(
    parameter int unsigned ADDR_WIDTH = 16,
    parameter int unsigned DATA_WIDTH = 32
) extends uvm_sequence_item;
  `uvm_object_param_utils(apb_transfer_c)

  // Request fields (driver consumes these to drive the transfer).
  rand bit                               pwrite;
  rand bit              [ADDR_WIDTH-1:0] addr;
  rand bit              [DATA_WIDTH-1:0] wdata;

  // Completion response fields (driver fills these after sampling).
  bit                   [DATA_WIDTH-1:0] rdata;
  bit                                    slverr;
  apb_transfer_status_e                  status;

  // Observation metadata (monitor/driver populate these).
  time                                   setup_time;
  time                                   access_time;
  time                                   completion_time;
  longint unsigned                       setup_cycle;
  longint unsigned                       access_cycle;
  longint unsigned                       completion_cycle;
  int unsigned                           wait_cycles;
  longint unsigned                       ordinal;
  int unsigned                           source_id;
  string                                 tag;

  // Intent metadata, not sampled from the pins.
  bit                                    expect_slverr;

  // Observation metadata: set by the monitor when any sampled value signal
  // (address/data/handshake) carried an X/Z during the transfer window, and
  // consumed by the checker's optional unknown-value policy.
  bit                                    unknown_sampled;

  extern function new(string name = "apb_transfer_c");
  extern function void do_copy(uvm_object rhs);
  extern function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  extern function void do_print(uvm_printer printer);
  extern function string convert2string();
endclass

/**
 * @brief Constructor for the APB transfer item.
 *
 * Initializes the transfer status to a defined default and calls the parent
 * constructor.
 *
 * @param name Object name.
 */
function apb_transfer_c::new(string name = "apb_transfer_c");
  super.new(name);
  status = APB_OK;
endfunction

/**
 * @brief Deep-copies all request, response, and metadata fields.
 *
 * @param rhs Source transfer object.
 */
function void apb_transfer_c::do_copy(uvm_object rhs);
  apb_transfer_c rhs_h;
  if (!$cast(rhs_h, rhs)) begin
    `uvm_fatal("TYPE_MISMATCH", $sformatf("do_copy: %s is not an apb_transfer_c",
                                          rhs.get_type_name()))
  end
  super.do_copy(rhs);

  // Request fields.
  pwrite           = rhs_h.pwrite;
  addr             = rhs_h.addr;
  wdata            = rhs_h.wdata;

  // Response fields.
  rdata            = rhs_h.rdata;
  slverr           = rhs_h.slverr;
  status           = rhs_h.status;

  // Observation metadata.
  setup_time       = rhs_h.setup_time;
  access_time      = rhs_h.access_time;
  completion_time  = rhs_h.completion_time;
  setup_cycle      = rhs_h.setup_cycle;
  access_cycle     = rhs_h.access_cycle;
  completion_cycle = rhs_h.completion_cycle;
  wait_cycles      = rhs_h.wait_cycles;
  ordinal          = rhs_h.ordinal;
  source_id        = rhs_h.source_id;
  tag              = rhs_h.tag;

  // Intent metadata.
  expect_slverr    = rhs_h.expect_slverr;

  // Observation metadata.
  unknown_sampled  = rhs_h.unknown_sampled;
endfunction

/**
 * @brief Compares all relevant request, response, and wait-count fields.
 *
 * Timing/ordinal/source-id/tag metadata, the intent flag expect_slverr, and
 * the observation flag unknown_sampled are transport/test context, not part
 * of a transfer match, so they are intentionally excluded — this lets a
 * driver response and a monitor transaction agree on the same transfer.
 *
 * @param rhs      Transfer to compare against.
 * @param comparer UVM comparer policy.
 * @return 1 on full match, 0 otherwise.
 */
function bit apb_transfer_c::do_compare(uvm_object rhs, uvm_comparer comparer);
  apb_transfer_c rhs_h;
  if (!super.do_compare(rhs, comparer)) return 0;
  if (!$cast(rhs_h, rhs)) return 0;
  if (pwrite !== rhs_h.pwrite || addr !== rhs_h.addr || wdata !== rhs_h.wdata ||
      rdata !== rhs_h.rdata || slverr !== rhs_h.slverr || status !== rhs_h.status ||
      wait_cycles !== rhs_h.wait_cycles)
    return 0;
  return 1;
endfunction

/**
 * @brief Prints all transfer fields via the UVM printer.
 *
 * @param printer UVM printer instance.
 */
function void apb_transfer_c::do_print(uvm_printer printer);
  super.do_print(printer);
  printer.print_field("pwrite", pwrite, 1, UVM_BIN);
  printer.print_field("addr", addr, ADDR_WIDTH, UVM_HEX);
  printer.print_field("wdata", wdata, DATA_WIDTH, UVM_HEX);
  printer.print_field("rdata", rdata, DATA_WIDTH, UVM_HEX);
  printer.print_field("slverr", slverr, 1, UVM_BIN);
  printer.print_string("status", status.name());
  printer.print_field("setup_time", setup_time, 64, UVM_TIME);
  printer.print_field("access_time", access_time, 64, UVM_TIME);
  printer.print_field("completion_time", completion_time, 64, UVM_TIME);
  printer.print_field("setup_cycle", setup_cycle, 64, UVM_DEC);
  printer.print_field("access_cycle", access_cycle, 64, UVM_DEC);
  printer.print_field("completion_cycle", completion_cycle, 64, UVM_DEC);
  printer.print_field("wait_cycles", wait_cycles, 32, UVM_DEC);
  printer.print_field("ordinal", ordinal, 64, UVM_DEC);
  printer.print_field("source_id", source_id, 32, UVM_DEC);
  printer.print_string("tag", tag);
  printer.print_field("expect_slverr", expect_slverr, 1, UVM_BIN);
  printer.print_field("unknown_sampled", unknown_sampled, 1, UVM_BIN);
endfunction

/**
 * @brief Returns a one-line string summary of the transfer.
 *
 * @return Formatted transfer summary.
 */
function string apb_transfer_c::convert2string();
  return {
    $sformatf(
        "%s addr=%h wdata=%h rdata=%h slverr=%0b wait=%0d ord=%0d src=%0d",
        pwrite ? "WR" : "RD",
        addr,
        wdata,
        rdata,
        slverr,
        wait_cycles,
        ordinal,
        source_id
    ),
    $sformatf(" status=%s tag=%s unknown=%0b", status.name(), tag, unknown_sampled)
  };
endfunction

// Binding typedef for the current non-parameterized apb_if specialization
// (16-bit PADDR, 32-bit PWDATA). The agent references widths through
// apb_transfer_t::ADDR_WIDTH / ::DATA_WIDTH so the values live in exactly one
// place; the config additionally validates them against $bits of the bound
// virtual interface.
typedef apb_transfer_c#(16, 32) apb_transfer_t;
