/**
 * @brief Directed single APB write sequence.
 *
 * Performs one APB write from caller-configured fields (address, write data,
 * slave-error expectation) and validates the observed response status.
 * Address/data come from the sequence fields or arguments — never from MAC
 * register constants — so any test can reuse it.
 */
class apb_write_sequence_c extends apb_sequence_base_c;
  `uvm_object_utils(apb_write_sequence_c)

  bit [apb_transfer_t::ADDR_WIDTH-1:0] m_addr;
  bit [apb_transfer_t::DATA_WIDTH-1:0] m_wdata;
  bit m_expect_slverr = 1'b0;
  bit m_check_response = 1'b1;
  apb_transfer_status_e m_expected_status = APB_OK;

  extern function new(string name = "apb_write_sequence_c");
  extern task body();
endclass

/**
 * @brief Constructor for the APB write sequence.
 *
 * Initializes the sequence by calling the parent class constructor.
 *
 * @param name Name of the sequence object.
 */
function apb_write_sequence_c::new(string name = "apb_write_sequence_c");
  super.new(name);
endfunction

/**
 * @brief Drives and checks one APB write.
 */
task apb_write_sequence_c::body();
  do_write(m_addr, m_wdata, m_expect_slverr);
  fetch_response();
  if (m_check_response) check_status(m_expected_status);
endtask
