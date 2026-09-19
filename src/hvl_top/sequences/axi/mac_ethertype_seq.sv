/**
 * @brief EtherType/Length-Type Field TX Verification Sequence.
 *
 * Single sequence class covering all seven directed and constrained-random
 * EtherType scenarios.  Extends axi_sequence_base_c and drives frames via
 * the AXI4-Stream TX interface; the scoreboard compares the expected RS
 * wire frame (from the reference model) against the actual RS TX monitor
 * capture.
 *
 * Scenario catalogue:
 *   1. scenario_basic()        — single 0x8808 frame
 *   2. scenario_boundary()     — 0x8807, 0x8808, 0x8809
 *   3. scenario_bitflip()      — 16 bit-flips of 0x8808
 *   4. scenario_malformed_ctrl() — wrong opcode / wrong DA
 *   5. scenario_typical()      — common Type + Length + invalid
 *   6. scenario_stress()       — mixed, B2B, constrained-random
 *   7. scenario_address()      — DA class alternation, SA vary
 */
class mac_ethertype_seq_c extends axi_sequence_base_c;
  `uvm_object_utils(mac_ethertype_seq_c)

  extern function new(string name = "mac_ethertype_seq_c");
  extern task body();
  extern task send_one(bit [15:0] et, int payload_len = 46);

  extern task scenario_basic();
  extern task scenario_boundary();
  extern task scenario_bitflip();
  extern task scenario_malformed_ctrl();
  extern task scenario_typical();
  extern task scenario_stress();
  extern task scenario_address();
endclass

function mac_ethertype_seq_c::new(string name = "mac_ethertype_seq_c");
  super.new(name);
endfunction

task mac_ethertype_seq_c::body();
  resolve_config();

  `uvm_info(get_type_name(), "--- Scenario 1: basic ---", UVM_MEDIUM)
  scenario_basic();

  `uvm_info(get_type_name(), "--- Scenario 2: boundary ---", UVM_MEDIUM)
  scenario_boundary();

  `uvm_info(get_type_name(), "--- Scenario 3: bitflip ---", UVM_MEDIUM)
  scenario_bitflip();

  `uvm_info(get_type_name(), "--- Scenario 4: malformed ctrl ---", UVM_MEDIUM)
  scenario_malformed_ctrl();

  `uvm_info(get_type_name(), "--- Scenario 5: typical ---", UVM_MEDIUM)
  scenario_typical();

  `uvm_info(get_type_name(), "--- Scenario 6: stress ---", UVM_MEDIUM)
  scenario_stress();

  `uvm_info(get_type_name(), "--- Scenario 7: address ---", UVM_MEDIUM)
  scenario_address();
endtask

// ---------------------------------------------------------------------------
// Helper — drive one frame with given EtherType and payload length
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::send_one(bit [15:0] et, int payload_len = 46);
  axi_item_c item;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
        ether_type      == et;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        payload.size()  == payload_len;
      }) begin
    `uvm_fatal(get_type_name(), $sformatf("Frame ET=%h randomization failed", et))
  end
  do_axi_item(item);
endtask

// ---------------------------------------------------------------------------
// 1. Basic — single valid frame with EtherType 0x8808
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_basic();
  axi_item_c item;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
        ether_type      == 16'h8808;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        payload.size()  == 46;
      }) begin
    `uvm_fatal(get_type_name(), "Basic 0x8808 frame randomization failed")
  end
  do_axi_item(item);
endtask

// ---------------------------------------------------------------------------
// 2. Boundary — adjacent values around 0x8808
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_boundary();
  axi_item_c item;
  bit [15:0] values[] = '{16'h8807, 16'h8808, 16'h8809};

  foreach (values[i]) begin
    item = axi_item_c::type_id::create($sformatf("item_%0d", i));
    if (!item.randomize() with {
          dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
          ether_type      == values[i];
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), $sformatf("Boundary frame ET=%h randomization failed", values[i]))
    end
    do_axi_item(item);
  end
endtask

// ---------------------------------------------------------------------------
// 3. Bit-flip — flip each bit of 0x8808, verify each changed value
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_bitflip();
  axi_item_c item;
  bit [15:0] base_val = 16'h8808;

  for (int i = 0; i < 16; i++) begin
    bit [15:0] flipped;
    flipped = base_val ^ (16'h0001 << i);
    item = axi_item_c::type_id::create($sformatf("flip_%0d", i));
    if (!item.randomize() with {
          dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
          ether_type      == flipped;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), $sformatf("Bit-flip frame ET=%h randomization failed", flipped))
    end
    do_axi_item(item);
  end
endtask

// ---------------------------------------------------------------------------
// 4. Malformed control — 0x8808 with wrong opcode or wrong DA
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_malformed_ctrl();
  axi_item_c item;
  bit [15:0] bad_opcodes[] = '{16'h0000, 16'h0002, 16'hFFFF};
  bit [47:0] bad_das[]     = '{48'hFF_FF_FF_FF_FF_FF,
                               48'h02_00_00_00_00_01,
                               48'h01_00_00_00_00_01};

  // Sub-scenario A: correct PAUSE DA, wrong opcode
  foreach (bad_opcodes[i]) begin
    item = axi_item_c::type_id::create($sformatf("bad_op_%0d", i));
    if (!item.randomize() with {
          dst_addr        == 48'h01_80_C2_00_00_01;
          ether_type      == 16'h8808;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), "Malformed ctrl (wrong opcode) randomization failed")
    end
    item.payload[0] = bad_opcodes[i][15:8];
    item.payload[1] = bad_opcodes[i][7:0];
    item.fcs = item.compute_fcs();
    do_axi_item(item);
  end

  // Sub-scenario B: correct opcode 0x0001, wrong DA
  foreach (bad_das[i]) begin
    item = axi_item_c::type_id::create($sformatf("bad_da_%0d", i));
    if (!item.randomize() with {
          dst_addr        == bad_das[i];
          ether_type      == 16'h8808;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), "Malformed ctrl (wrong DA) randomization failed")
    end
    item.payload[0] = 8'h00;
    item.payload[1] = 8'h01;
    item.fcs = item.compute_fcs();
    do_axi_item(item);
  end
endtask

// ---------------------------------------------------------------------------
// 5. Typical / special — common Type values, Length boundary, invalid range
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_typical();
  axi_item_c item;
  bit [15:0] values[] = '{
    16'h0800,  // IPv4
    16'h86DD,  // IPv6
    16'h0806,  // ARP
    16'h8100,  // VLAN tag
    16'h8847,  // MPLS unicast
    16'h88CC,  // LLDP
    16'h05DC,  // max Length field (1500)
    16'h05DD,  // first invalid value (1501)
    16'h05FF,  // last invalid value (1535)
    16'h0600   // min Type field (1536)
  };

  foreach (values[i]) begin
    item = axi_item_c::type_id::create($sformatf("typical_%0d", i));
    if (!item.randomize() with {
          dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
          ether_type      == values[i];
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), $sformatf("Typical frame ET=%h randomization failed", values[i]))
    end
    do_axi_item(item);
  end
endtask

// ---------------------------------------------------------------------------
// 6. Stress — data->control->data, back-to-back, constrained-random sweep
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_stress();
  bit [15:0] rand_et;

  // Sub-scenario A: data -> control -> data
  `uvm_info(get_type_name(), "Stress: data -> control -> data", UVM_MEDIUM)
  send_one(16'h0800);  // data (IPv4)
  send_one(16'h8808);  // control (MAC Control)
  send_one(16'h0800);  // data (IPv4)

  // Sub-scenario B: back-to-back independent frames (minimum IFG)
  `uvm_info(get_type_name(), "Stress: 10 back-to-back frames", UVM_MEDIUM)
  repeat (10) begin
    if (!std::randomize(rand_et) with { rand_et > 16'h0600; }) begin
      `uvm_fatal(get_type_name(), "Random ET randomization failed")
    end
    send_one(rand_et, $urandom_range(46, 256));
  end

  // Sub-scenario C: constrained-random length/type sweep (20 frames)
  // Weighted: 40% Type > 0x0600, 30% Length <= 0x05DC, 20% 0x8808, 10% invalid 0x05DD-0x05FF
  `uvm_info(get_type_name(), "Stress: constrained-random ET sweep (20 frames)", UVM_MEDIUM)
  repeat (20) begin
    bit [2:0] category;
    bit [15:0] sweep_et;
    int unsigned pld_len;
    if (!std::randomize(category) with {
          category dist { [0:1] := 40,   // Type > 0x0600
                         [2:3] := 30,   // Length <= 0x05DC
                         [4:5] := 20,   // 0x8808
                         [6:7] := 10 }; // invalid 0x05DD-0x05FF
        }) begin
      `uvm_fatal(get_type_name(), "Category randomization failed")
    end
    case (category)
      0, 1: begin  // Type > 0x0600
        if (!std::randomize(sweep_et) with { sweep_et > 16'h0600; sweep_et != 16'h8808; })
          `uvm_fatal(get_type_name(), "Type ET randomization failed")
        pld_len = 46;
      end
      2, 3: begin  // Length <= 0x05DC — set payload to match length to avoid length error
        if (!std::randomize(sweep_et) with { sweep_et >= 16'h002E; sweep_et <= 16'h05DC; })
          `uvm_fatal(get_type_name(), "Length ET randomization failed")
        pld_len = int'(sweep_et);
      end
      4, 5: begin  // 0x8808
        sweep_et = 16'h8808;
        pld_len  = 46;
      end
      default: begin  // invalid 0x05DD-0x05FF
        if (!std::randomize(sweep_et) with { sweep_et >= 16'h05DD; sweep_et <= 16'h05FF; })
          `uvm_fatal(get_type_name(), "Invalid ET randomization failed")
        pld_len = 46;
      end
    endcase
    send_one(sweep_et, pld_len);
  end
endtask

// ---------------------------------------------------------------------------
// 7. Address — DA class alternation, SA variation, random DA+ET combos
// ---------------------------------------------------------------------------
task mac_ethertype_seq_c::scenario_address();
  axi_item_c item;
  // Sub-scenario A: alternate broadcast / multicast / unicast DA
  bit [47:0] da_class_seq[] = '{
    48'hFF_FF_FF_FF_FF_FF,  // broadcast
    48'h01_00_00_00_00_00,  // multicast (bit0 of first byte = 1)
    48'h00_10_A4_00_00_01,  // unicast
    48'hFF_FF_FF_FF_FF_FF,  // broadcast
    48'h03_00_00_00_00_00,  // multicast
    48'h00_1A_2B_3C_4D_5E   // unicast
  };
  // Sub-scenario B: SA variations
  bit [47:0] sa_vals[] = '{
    48'h00_00_00_00_00_00,  // all zeros
    48'hFF_FF_FF_FF_FF_FF,  // all ones
    48'h02_00_00_00_00_01,  // incrementing
    48'hAA_BB_CC_DD_EE_FF   // pattern
  };

  // Sub-scenario A: DA class alternation (6 frames)
  `uvm_info(get_type_name(), "Address: DA class alternation", UVM_MEDIUM)
  foreach (da_class_seq[i]) begin
    item = axi_item_c::type_id::create($sformatf("da_class_%0d", i));
    if (!item.randomize() with {
          dst_addr        == da_class_seq[i];
          ether_type      == 16'h0800;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), $sformatf("DA class frame %0d randomization failed", i))
    end
    do_axi_item(item);
  end

  // Sub-scenario B: SA variation (4 frames)
  `uvm_info(get_type_name(), "Address: SA variation", UVM_MEDIUM)
  foreach (sa_vals[i]) begin
    item = axi_item_c::type_id::create($sformatf("sa_var_%0d", i));
    if (!item.randomize() with {
          dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
          src_addr        == sa_vals[i];
          ether_type      == 16'h0800;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), $sformatf("SA variation frame %0d randomization failed", i))
    end
    do_axi_item(item);
  end

  // Sub-scenario C: constrained-random DA + ET combinations (5 frames)
  `uvm_info(get_type_name(), "Address: random DA + ET combos", UVM_MEDIUM)
  repeat (5) begin
    bit [47:0] rand_da;
    bit [15:0] rand_et;
    if (!std::randomize(rand_da, rand_et) with {
          rand_et inside {16'h0800, 16'h8100, 16'h86DD, 16'h8808};
        }) begin
      `uvm_fatal(get_type_name(), "Random DA+ET randomization failed")
    end
    item = axi_item_c::type_id::create("rand_combo");
    if (!item.randomize() with {
          dst_addr        == rand_da;
          ether_type      == rand_et;
          crc_error       == 0;
          length_error    == 0;
          alignment_error == 0;
          insert_fcs      == 1;
          payload.size()  == 46;
        }) begin
      `uvm_fatal(get_type_name(), "Random DA+ET frame randomization failed")
    end
    do_axi_item(item);
  end
endtask
