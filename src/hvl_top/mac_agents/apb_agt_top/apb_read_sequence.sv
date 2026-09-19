/**
 * @brief Directed single APB read sequence.
 *
 * Performs one APB read from a caller-configured address (plus optional
 * slave-error expectation) and validates the observed response status. The
 * sampled read data and response status are published to the caller through
 * the public m_rdata/m_status fields.
 */
class apb_read_sequence_c extends apb_sequence_base_c;
  `uvm_object_utils(apb_read_sequence_c)

  bit [apb_transfer_t::ADDR_WIDTH-1:0] m_addr;
  bit m_expect_slverr = 1'b0;
  bit m_check_response = 1'b1;
  apb_transfer_status_e m_expected_status = APB_OK;

  // Sampled read data and response status, set when body() completes.
  bit [apb_transfer_t::DATA_WIDTH-1:0] m_rdata;
  apb_transfer_status_e m_status;

  extern function new(string name = "apb_read_sequence_c");
  extern task body();
endclass

/**
 * @brief Constructor for the APB read sequence.
 *
 * Initializes the sequence by calling the parent class constructor.
 *
 * @param name Name of the sequence object.
 */
function apb_read_sequence_c::new(string name = "apb_read_sequence_c");
  super.new(name);
endfunction

/**
 * @brief Drives, checks, and returns the result of one APB read.
 */
task apb_read_sequence_c::body();
  do_read(m_addr, m_expect_slverr);
  fetch_response();
  m_rdata  = m_rsp.rdata;
  m_status = m_rsp.status;
  if (m_check_response) check_status(m_expected_status);
endtask
