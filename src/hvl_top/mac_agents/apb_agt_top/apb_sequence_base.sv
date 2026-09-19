// APB-specific report IDs shared across the agent (C-14). Distinct from the
// interface assertion IDs (APB_ASSERT) and the checker IDs (APB_PROTOCOL) so
// triage is unambiguous; the driver reuses the timeout/reset-abort IDs here.
localparam string APB_RESPONSE_ID = "APB_RESPONSE";
localparam string APB_SLV_EXPECTED_ID = "APB_SLV_EXPECTED";
localparam string APB_SLV_UNEXPECTED_ID = "APB_SLV_UNEXPECTED";
localparam string APB_TIMEOUT_ID = "APB_TIMEOUT";
localparam string APB_RESET_ABORT_ID = "APB_RESET_ABORT";
localparam string APB_PROTOCOL_ID = "APB_PROTOCOL";
localparam string APB_RAND_FAIL_ID = "APB_RAND_FAIL";

/**
 * @brief Base sequence for APB transfers.
 *
 * Owns reusable helpers for a single write, a single read, response
 * retrieval, expected-status checking, and formatted failure diagnostics.
 * Helpers take address/data/expectation from explicit arguments — never from
 * MAC register constants — so any test or virtual sequence can reuse them.
 */
class apb_sequence_base_c extends uvm_sequence #(apb_transfer_c);
  `uvm_object_utils(apb_sequence_base_c)

  // Completed response copy for the most recent transfer (from fetch_response).
  apb_transfer_c m_rsp;

  extern function new(string name = "apb_sequence_base_c");
  extern task do_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       bit [apb_transfer_t::DATA_WIDTH-1:0] wdata, bit expect_slverr = 1'b0);
  extern task do_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr, bit expect_slverr = 1'b0);
  extern task fetch_response();
  extern task check_status(apb_transfer_status_e expected);
  extern function void report_failure(apb_transfer_status_e expected);
endclass

/**
 * @brief Constructor for the APB base sequence.
 *
 * Initializes the sequence by calling the parent class constructor.
 *
 * @param name Name of the sequence object.
 */
function apb_sequence_base_c::new(string name = "apb_sequence_base_c");
  super.new(name);
endfunction

/**
 * @brief Creates and starts a single APB write transfer.
 *
 * Builds a request item from the supplied address, write data, and error
 * expectation, then drives it through start_item/finish_item. The completion
 * response is retrieved separately with fetch_response().
 *
 * @param addr          Transfer address.
 * @param wdata         Write data.
 * @param expect_slverr Intent: the test expects PSLVERR on this access.
 */
task apb_sequence_base_c::do_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                   bit [apb_transfer_t::DATA_WIDTH-1:0] wdata,
                                   bit expect_slverr = 1'b0);
  apb_transfer_t item = apb_transfer_t::type_id::create("write_item");
  item.pwrite        = 1'b1;
  item.addr          = addr;
  item.wdata         = wdata;
  item.expect_slverr = expect_slverr;
  start_item(item);
  finish_item(item);
endtask

/**
 * @brief Creates and starts a single APB read transfer.
 *
 * Builds a request item from the supplied address and error expectation,
 * then drives it through start_item/finish_item. The completion response is
 * retrieved separately with fetch_response().
 *
 * @param addr          Transfer address.
 * @param expect_slverr Intent: the test expects PSLVERR on this access.
 */
task apb_sequence_base_c::do_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                  bit expect_slverr = 1'b0);
  apb_transfer_t item = apb_transfer_t::type_id::create("read_item");
  item.pwrite        = 1'b0;
  item.addr          = addr;
  item.expect_slverr = expect_slverr;
  start_item(item);
  finish_item(item);
endtask

/**
 * @brief Retrieves the completed driver response for the previous transfer.
 *
 * Blocks until the driver returns the response for the item finished by
 * do_write/do_read and stores the copy in m_rsp. Must be called exactly once
 * per transferred item when responses are consumed.
 */
task apb_sequence_base_c::fetch_response();
  get_response(m_rsp);
endtask

/**
 * @brief Validates the fetched response status against an expectation.
 *
 * Reports a formatted APB failure when the observed status differs from the
 * expected status, and logs expected slave errors as informational only.
 *
 * @param expected Expected response status.
 */
task apb_sequence_base_c::check_status(apb_transfer_status_e expected);
  if (m_rsp == null) begin
    `uvm_fatal(APB_RESPONSE_ID, "check_status: no response fetched (call fetch_response first)")
  end
  if (m_rsp.status == expected) begin
    if (expected == APB_SLVERR)
      `uvm_info(APB_SLV_EXPECTED_ID, $sformatf(
                "expected PSLVERR observed: %s", m_rsp.convert2string()), UVM_MEDIUM)
  end else begin
    report_failure(expected);
  end
endtask

/**
 * @brief Reports a formatted APB response/status mismatch.
 *
 * @param expected Expected response status.
 */
function void apb_sequence_base_c::report_failure(apb_transfer_status_e expected);
  `uvm_error(APB_RESPONSE_ID, $sformatf(
             "APB response mismatch: expected status=%0s observed status=%0s %s",
             expected.name(),
             m_rsp.status.name(),
             m_rsp.convert2string()
             ))
endfunction
