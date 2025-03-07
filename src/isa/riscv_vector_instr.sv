/*
 * Copyright 2020 Google LLC
 * Copyright 2020 Andes Technology Co., Ltd.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


// Base class for RISC-V vector exenstion ISA, implmented based on spec v0.8
class riscv_vector_instr extends riscv_floating_point_instr;

  rand riscv_vreg_t vs1;
  rand riscv_vreg_t vs2;
  rand riscv_vreg_t vs3;
  rand riscv_vreg_t vd;
  rand va_variant_t va_variant;
  rand bit          vm;
  rand bit          wd;
  rand bit [10:0]   eew;
  bit               has_vd = 1'b1;
  bit               has_vs1 = 1'b1;
  bit               has_vs2 = 1'b1;
  bit               has_vs3 = 1'b1;
  bit               has_vm = 1'b0;
  bit               has_va_variant;
  bit               is_widening_instr;
  bit               is_narrowing_instr;
  bit               is_quad_widening_instr;
  bit               is_convert_instr;
  va_variant_t      allowed_va_variants[$];
  string            sub_extension;
  rand bit [2:0]    nfields; // Used by segmented load/store
  rand bit [3:0]    emul;

  constraint avoid_reserved_vregs_c {
    if (m_cfg.vector_cfg.reserved_vregs.size() > 0) {
	  if (is_widening_instr) {
        foreach (m_cfg.vector_cfg.reserved_vregs[i]) {
	      !(m_cfg.vector_cfg.reserved_vregs[i] inside {[vd:(vd + 2 * m_cfg.vector_cfg.vtype.vlmul - 1)]});
		}
	  }
	  else {
		foreach (m_cfg.vector_cfg.reserved_vregs[i]) {
	      !(m_cfg.vector_cfg.reserved_vregs[i] inside {[vd:(vd + m_cfg.vector_cfg.vtype.vlmul - 1)]});
		}
	  }
    }
  }

  constraint va_variant_c {
    if (has_va_variant) {
      va_variant inside {allowed_va_variants};
    }
  }
  
   // hcheng: Temporary constraint as XS3 VPU haven't supported masking yet.
  constraint avoid_masking_c {
	soft vm == 1'b1;
  }

  // Section 3.3.2: Vector Register Grouping (vlmul)
  // Instructions specifying a vector operand with an odd-numbered vector register will raisean
  // illegal instruction exception.
  // TODO: Exclude the instruction that ignore VLMUL
  // TODO: Update this constraint for fractional LMUL
  constraint operand_group_c {
    if (m_cfg.vector_cfg.vtype.vlmul > 0) {
      vd  % m_cfg.vector_cfg.vtype.vlmul == 0;
      vs1 % m_cfg.vector_cfg.vtype.vlmul == 0;
      vs2 % m_cfg.vector_cfg.vtype.vlmul == 0;
      vs3 % m_cfg.vector_cfg.vtype.vlmul == 0;
    }
  }

  // Section 11.2: Widening Vector Arithmetic Instructions
  constraint widening_instr_c {
    if (is_widening_instr) {
     // The destination vector register group results are arranged as if both
     // SEW and LMUL were at twice their current settings.
     vd % (m_cfg.vector_cfg.vtype.vlmul * 2) == 0;
     // The destination vector register group cannot overlap a source vector
     // register group of a different element width (including the mask register if masked)
     !(vs1 inside {[vd : vd + m_cfg.vector_cfg.vtype.vlmul * 2 - 1]});
     !(vs2 inside {[vd : vd + m_cfg.vector_cfg.vtype.vlmul * 2 - 1]});
     (vm == 0) -> (vd != 0);
     // Double-width result, first source double-width, second source single-width
     if (va_variant inside {WV, WX, WF}) {
       vs2 % (m_cfg.vector_cfg.vtype.vlmul * 2) == 0;
     }
    }
  }

  // Section 11.3: Narrowing Vector Arithmetic Instructions
  constraint narrowing_instr_c {
    if (is_narrowing_instr) {
      // The source and destination vector register numbers must be aligned
      // appropriately for the vector registergroup size
      vs2 % (m_cfg.vector_cfg.vtype.vlmul * 2) == 0;
      // The destination vector register group cannot overlap the rst source
      // vector register group (specied by vs2)
      !(vd inside {[vs2 : vs2 + m_cfg.vector_cfg.vtype.vlmul * 2 - 1]});
      // The destination vector register group cannot overlap the mask register
      // if used, unless LMUL=1 (implemented in vmask_overlap_c)
    }
  }

  // 12.3. Vector Integer Add-with-Carry / Subtract-with-Borrow Instructions
  constraint add_sub_with_carry_c {
    if (m_cfg.vector_cfg.vtype.vlmul > 1) {
      // For vadc and vsbc, an illegal instruction exception is raised if the
      // destination vector register is v0 and LMUL> 1
      if (instr_name inside {VADC, VSBC}) {
        vd != 0;
      }
      // For vmadc and vmsbc, an illegal instruction exception is raised if the
      // destination vector register overlaps asource vector register group and LMUL > 1
      if (instr_name inside {VMADC, VMSBC}) {
        vd != vs2;
        vd != vs1;
      }
    }
  }

  // 12.7. Vector Integer Comparison Instructions
  // For all comparison instructions, an illegal instruction exception is raised if the
  // destination vector register overlaps a source vector register group and LMUL > 1
  constraint compare_instr_c {
    if (category == COMPARE) {
      vd != vs2;
      vd != vs1;
    }
  }

  // 16.8. Vector Iota Instruction
  // An illegal instruction exception is raised if the destination vector register group
  // overlaps the source vector mask register. If the instruction is masked, an illegal
  // instruction exception is issued if the destination vector register group overlaps v0.
  constraint vector_itoa_msbf_c {
    if (instr_name inside {VIOTA_M, VMSBF_M}) {
      vd != vs2;
      (vm == 0) -> (vd != 0);
    }
  }

  constraint vector_vmsif_vmsof_c{
	  if (instr_name inside {VMSIF_M, VMSOF_M}) {
		vd != vs2;
        (vm == 0) -> (vd != 0);
	  }
  }

  // 16.9. Vector Element Index Instruction
  // The vs2 eld of the instruction must be set to v0, otherwise the encoding is reserved
  constraint vector_element_index_c {
    if (instr_name == VID_V) {
      vs2 == 0;
      // TODO; Check if this constraint is needed
      vd != vs2;
    }
  }

  // Section 17.3  Vector Slide Instructions
  // The destination vector register group for vslideup cannot overlap the vector register
  // group of the source vector register group or the mask register
  constraint vector_slide_c {
    if (instr_name inside {VSLIDEUP, VSLIDE1UP, VSLIDEDOWN, VSLIDE1DOWN, VFSLIDE1UP, VFSLIDE1DOWN}) {
      vd != vs2;
      vd != vs1;
      (vm == 0) -> (vd != 0);
    }
  }

  // Section 17.4: Vector Register Gather Instruction
  // For any vrgather instruction, the destination vector register group cannot overlap
  // with the source vector register group
  constraint vector_gather_c {
    if (instr_name inside {VRGATHER, VRGATHEREI16}) {
      vd != vs2;
      vd != vs1;
      (vm == 0) -> (vd != 0);
    }
  }

  // Section 17.5: Vector compress instruction
  // The destination vector register group cannot overlap the source vector register
  // group or the source vector mask register
  constraint vector_compress_c {
    if (instr_name == VCOMPRESS) {
      vd != vs2;
      vd != vs1;
      (vm == 0) -> (vd != 0);
    }
  }

  // Section 7.8. Vector Load/Store Segment Instructions
  // The LMUL setting must be such that LMUL * NFIELDS <= 8
  // Vector register numbers accessed by the segment load or store would increment
  // cannot past 31
  // hcheng: move the condition to check segmented load/store subextension to pre_randomize()
  constraint nfields_c {
    solve emul before nfields;
	if (category inside {LOAD, STORE} && !(instr_name inside {VLRE_V, VSR_V})) {
      if (m_cfg.vector_cfg.vtype.vlmul < 8 && emul < 8) {
	    // TODO: Check gcc compile issue with nfields == 0
	    nfields > 0;
	  	
	  	(nfields + 1) * m_cfg.vector_cfg.vtype.vlmul <= 8;
	    (nfields + 1) * emul <= 8;
	    if (category == LOAD) {
		  if(instr_name inside {VLUXEI_V, VLOXEI_V, VLUXSEGEI_V,VLOXSEGEI_V}) {
			vd + (nfields + 1) * m_cfg.vector_cfg.vtype.vlmul - 1 <= 31;
			vs2 + (nfields + 1) * emul - 1 <= 31;
		  }
		  else {
			vd + (nfields + 1) * emul - 1 <= 31; 
		  }
	    }
	    if (category == STORE) {
		  if(instr_name inside {VSUXEI_V, VSOXEI_V, VSUXSEGEI_V, VSOXSEGEI_V}) {
			vs3 + (nfields + 1) * m_cfg.vector_cfg.vtype.vlmul - 1 <= 31;
			vs2 + (nfields + 1) * emul - 1 <= 31;
		  }
		  else {
			vs3 + (nfields + 1) * emul - 1 <= 31; 
		  }
	    }
      }
      else {
	    nfields == 0;
      }
	}
  }
  // Section 7.9 NFIELDS can only be 1, 2, 4, 8 for whole-register load/store
  constraint nfields_whole_reg_c {
	  if(instr_name inside {VLRE_V, VSR_V}) {
	    nfields inside {0, 1, 3, 7};
	    if (category == LOAD) {
          vd + nfields <= 31;
		  vd % (nfields + 1) == 0; 
	    }
	    if (category == STORE) {
          vs3 + nfields <= 31;
		  vs3 % (nfields + 1) == 0; 
	    }
	  }
  }

  constraint vmv_alignment_c {
    if (instr_name == VMV2R_V) {
      int'(vs2) % 2 == 0;
      int'(vd)  % 2 == 0;
    }
    if (instr_name == VMV4R_V) {
      int'(vs2) % 4 == 0;
      int'(vd)  % 4 == 0;
    }
    if (instr_name == VMV8R_V) {
      int'(vs2) % 8 == 0;
      int'(vd)  % 8 == 0;
    }
  }

  /////////////////// Vector mask constraint ///////////////////

  // Section 5.3
  // The destination vector register group for a masked vector instruction can only overlap
  // the source mask register (v0) when LMUL=1
  constraint vmask_overlap_c {
    (vm == 0) && (m_cfg.vector_cfg.vtype.vlmul > 1) -> (vd != 0);
  }

  constraint vector_mask_enable_c {
    // Below instruction is always masked
    if (instr_name inside {VMERGE, VFMERGE, VADC, VSBC, VMADC, VMSBC}) {
	  if (va_variant inside {VVM, VIM, VXM, VFM}) {
        vm == 1'b0;
	  }
	  else{
		vm == 1'b1;
	  }
    }
  }

  constraint vector_mask_disable_c {
    // (vm=0) is reserved for below ops
    if (instr_name inside {VMV, VFMV, VCOMPRESS, VFMV_F_S, VFMV_S_F, VMV_X_S, VMV_S_X,
                           VMV1R_V, VMV2R_V, VMV4R_V, VMV8R_V, VLM_V, VSM_V, VLRE_V, VSR_V}) {
      vm == 1'b1;
    }
  }

  // 16.1. Vector Mask-Register Logical Instructions
  // No vector mask for these instructions
  constraint vector_mask_instr_c {
    if (instr_name inside {[VMAND_MM : VMXNOR_MM]}) {
      vm == 1'b1;
    }
  }

  constraint disable_floating_point_varaint_c {
    if (!m_cfg.vector_cfg.vec_fp) {
      va_variant != VF;
    }
  }

  constraint vector_load_store_mask_overlap_c {
    // TODO: Check why this is needed?
    if (category == STORE) {
      (vm == 0) -> (vs3 != 0);
	  !(vs2 inside {[vs3 : vs3 + m_cfg.vector_cfg.vtype.vlmul * (nfields + 1) - 1]});
	  !((vs2 + emul - 1) inside {[vs3 : vs3 + m_cfg.vector_cfg.vtype.vlmul * (nfields + 1) - 1]});
    }
    // 7.8.3 For vector indexed segment loads, the destination vector register groups
    // cannot overlap the source vectorregister group (specied by vs2), nor can they
    // overlap the mask register if masked
    // AMO instruction uses indexed address mode
    if (format == VLX_FORMAT) {
	  !(vs2 inside {[vd : vd + m_cfg.vector_cfg.vtype.vlmul * (nfields + 1) - 1]});
	  !((vs2 + emul - 1) inside {[vd : vd + m_cfg.vector_cfg.vtype.vlmul * (nfields + 1) - 1]});
    }
  }

  // load/store EEW/EMUL and corresponding register grouping constraints
  constraint load_store_solve_order_c {
    solve eew before emul;
    solve emul before vd;
    solve emul before vs1;
    solve emul before vs2;
    solve emul before vs3;
  }

  constraint load_store_eew_emul_c {
    if (category inside {LOAD, STORE}) {
      eew inside {m_cfg.vector_cfg.legal_eew};
	  if (eew < m_cfg.vector_cfg.vtype.vsew) {
		  emul == 1;
	  }
	  else {
	    emul == eew / m_cfg.vector_cfg.vtype.vsew * m_cfg.vector_cfg.vtype.vlmul;
	  }
      if (emul > 1) {
	    if (category == LOAD) {
		  if(instr_name inside {VLUXEI_V, VLOXEI_V, VLUXSEGEI_V,VLOXSEGEI_V}) {
			// vd % m_cfg.vector_cfg.vtype.vlmul == 0; // duplicated
			vs2 % emul == 0;
		  }
		  else {
			vd % emul == 0;
		  }
	    }
	    if (category == STORE) {
		  if(instr_name inside {VSUXEI_V, VSOXEI_V, VSUXSEGEI_V, VSOXSEGEI_V}) {
			// vs3 % m_cfg.vector_cfg.vtype.vlmul == 0; // duplicated
			vs2 % emul == 0;
		  }
		  else {
			vs3 % emul == 0;
		  }
	    }
      }
    }
  }
  
  constraint vlm_vsm_c {
	  if (instr_name inside {VLM_V, VSM_V}) {
		  eew == 8;
		  emul == 1;
	  }
  }
  // Some temporarily constraint to avoid illegal instruction
  // TODO: Review these constraints
  constraint temp_c {
    (vm == 0) -> (vd != 0);
  }

  // Constraints for upgrading to RVV 1.0
  
  // vzext.vf2/4/8, vsext.vf2/4/8 constraints
  constraint vzext_vsext_c{
	if (instr_name inside {VZEXT, VSEXT}) {
      m_cfg.vector_cfg.vtype.vsew / eew inside {2, 4, 8};
	  eew >= 8;
	  vd != vs2;
    }
  }
  
  
  `uvm_object_utils(riscv_vector_instr)
  `uvm_object_new

  // Filter unsupported instructions based on configuration
  virtual function bit is_supported(riscv_instr_gen_config cfg);
    string name = instr_name.name();
    // 19.2.2. Vector Add with Carry/Subtract with Borrow Reserved under EDIV>1
    if ((cfg.vector_cfg.vtype.vediv > 1) &&
        (instr_name inside {VADC, VSBC, VMADC, VMSBC})) begin
      return 1'b0;
    end
    // Disable widening/narrowing instruction when LMUL == 8
    if ((!cfg.vector_cfg.vec_narrowing_widening) &&
        (is_widening_instr || is_narrowing_instr)) begin
	  `uvm_info(`gfn, $sformatf("Kicking out widening/narrowing vector FP: %0s", name), UVM_LOW)
      return 1'b0;
    end
    if (!cfg.vector_cfg.vec_quad_widening && is_quad_widening_instr) begin
      return 1'b0;
    end
    // TODO: Clean up this list, it's causing gcc compile error now
    // hcheng: Comment to enable the instructions in the list
    // if (instr_name inside {VWMACCSU, VMERGE, VFMERGE, VMADC, VMSBC}) begin
    //  return 1'b0;
    //end
    
    // The standard vector floating-point instructions treat 16-bit, 32-bit, 64-bit,
    // and 128-bit elements as IEEE-754/2008-compatible values. If the current SEW does
    // not correspond to a supported IEEE floating-pointtype, an illegal instruction
    // exception is raised
    if (!cfg.vector_cfg.vec_fp) begin
      if ((name.substr(0, 1) == "VF") || (name.substr(0, 2) == "VMF")) begin
	    `uvm_info(`gfn, $sformatf("Skipping vector FP: %0s", name), UVM_LOW)
        return 1'b0;
      end
    end
    if ((cfg.vector_cfg.vtype.vsew == 8) && 
	    (instr_name inside {VZEXT, VSEXT})) begin
	  return 1'b0;
	end
    return 1'b1;
  endfunction

  virtual function string get_instr_name();
    string name = super.get_instr_name();
    if (category inside {LOAD, STORE}) begin
      // Add eew before ".v" or "ff.v" suffix
      if (instr_name inside {VLEFF_V, VLSEGEFF_V}) begin
        name = name.substr(0, name.len() - 5);
        name = $sformatf("%0s%0dFF.V", name, eew);
      end else if (instr_name inside {VLM_V, VSM_V, VSR_V}) begin 
	    // do nothing to just return name as-is
	  end else begin
        name = name.substr(0, name.len() - 3);
        name = $sformatf("%0s%0d.V", name, eew);
      end
      `uvm_info(`gfn, $sformatf("%0s -> %0s", super.get_instr_name(), name), UVM_LOW)
    end
    if (instr_name inside {VZEXT, VSEXT}) begin
	  name = $sformatf("%0s.VF%0d", name, m_cfg.vector_cfg.vtype.vsew / eew);
	  `uvm_info(`gfn, $sformatf("%0s -> %0s", super.get_instr_name(), name), UVM_LOW)
	end
    return name;
  endfunction

  // Convert the instruction to assembly code
  virtual function string convert2asm(string prefix = "");
    string asm_str;
    case (format)
      VS2_FORMAT: begin
        if (instr_name == VID_V) begin
          asm_str = $sformatf("vid.v %s", vd.name());
        end else if (instr_name inside {VPOPC_M, VFIRST_M}) begin
          asm_str = $sformatf("%0s %0s,%0s", get_instr_name(), rd.name(), vs2.name());
        end else begin
	      asm_str = $sformatf("%0s ", get_instr_name());
	      asm_str = format_string(asm_str, MAX_INSTR_STR_LEN);
	      asm_str = {asm_str, $sformatf("%0s,%0s", vd.name(), vs2.name())};
        end
      end
      VA_FORMAT: begin
        if (instr_name == VMV) begin
          case (va_variant)
            VV: asm_str = $sformatf("vmv.v.v %s,%s", vd.name(), vs1.name());
            VX: asm_str = $sformatf("vmv.v.x %s,%s", vd.name(), rs1.name());
            VI: asm_str = $sformatf("vmv.v.i %s,%s", vd.name(), imm_str);
            default: `uvm_info(`gfn, $sformatf("Unsupported va_variant %0s", va_variant), UVM_LOW)
          endcase
        end else if (instr_name == VFMV) begin
          asm_str = $sformatf("vfmv.v.f %s,%s", vd.name(), fs1.name());
        end else if (instr_name == VMV_X_S) begin
          asm_str = $sformatf("vmv.x.s %s,%s", rd.name(), vs2.name());
        end else if (instr_name == VMV_S_X) begin
          asm_str = $sformatf("vmv.s.x %s,%s", vd.name(), rs1.name());
        end else if (instr_name == VFMV_F_S) begin
          asm_str = $sformatf("vfmv.f.s %s,%s", fd.name(), vs2.name());
        end else if (instr_name == VFMV_S_F) begin
          asm_str = $sformatf("vfmv.s.f %s,%s", vd.name(), fs1.name());
        end else begin
          if (!has_va_variant) begin
            asm_str = $sformatf("%0s ", get_instr_name());
            asm_str = format_string(asm_str, MAX_INSTR_STR_LEN);
            asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), vs1.name())};
          end else begin
            asm_str = $sformatf("%0s.%0s ", get_instr_name(), va_variant.name());
            asm_str = format_string(asm_str, MAX_INSTR_STR_LEN);
            case (va_variant) inside
              WV, VV, VVM, VM: begin
                asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), vs1.name())};
              end
              WI, VI, VIM: begin
                asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), imm_str)};
              end
              VF, VFM: begin
                if (instr_name inside {VFMADD, VFNMADD, VFMACC, VFNMACC, VFNMSUB, VFWNMSAC,
                                       VFWMACC, VFMSUB, VFMSAC, VFNMSAC, VFWNMACC, VFWMSAC}) begin
                  asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), fs1.name(), vs2.name())};
                end else begin
                  asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), fs1.name())};
                end
              end
              WX, VX, VXM: begin
                if (instr_name inside {VMADD, VNMSUB, VMACC, VNMSAC, VWMACCSU, VWMACCU,
                                       VWMACCUS, VWMACC}) begin
                  asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), rs1.name(), vs2.name())};
                end else begin
                  asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), rs1.name())};
                end
              end
              WF: begin
                asm_str = {asm_str, $sformatf("%0s,%0s,%0s", vd.name(), vs2.name(), fs1.name())};
              end
            endcase
          end
        end
      end
      VL_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
	      if(instr_name == VLRE_V) begin
		    asm_str = $sformatf("%0s %s,(%s)", add_nfields(get_instr_name(), 2),
                                             vd.name(), rs1.name());  
	      end else begin
            asm_str = $sformatf("%0s %s,(%s)", add_nfields(get_instr_name(), 5),
                                             vd.name(), rs1.name());
		  end
        end else begin
          asm_str = $sformatf("%0s %s,(%s)", get_instr_name(), vd.name(), rs1.name());
        end
      end
      VS_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
	      if(instr_name == VSR_V) begin
		    asm_str = $sformatf("%0s %s,(%s)", add_nfields(get_instr_name(), 2),
                                             vs3.name(), rs1.name());
          end else begin
            asm_str = $sformatf("%0s %s,(%s)", add_nfields(get_instr_name(), 5),
                                             vs3.name(), rs1.name());
	      end
        end else begin
          asm_str = $sformatf("%0s %s,(%s)", get_instr_name(), vs3.name(), rs1.name());
        end
      end
      VLS_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", add_nfields(get_instr_name(), 6),
                                                   vd.name(), rs1.name(), rs2.name());
        end else begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", get_instr_name(),
                                                   vd.name(), rs1.name(), rs2.name());
        end
      end
      VSS_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", add_nfields(get_instr_name(), 6),
                                                   vs3.name(), rs1.name(), rs2.name());
        end else begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", get_instr_name(),
                                                   vs3.name(), rs1.name(), rs2.name());
        end
      end
      VLX_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", add_nfields(get_instr_name(), 7),
                                                   vd.name(), rs1.name(), vs2.name());
        end else begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", get_instr_name(),
                                                   vd.name(), rs1.name(), vs2.name());
        end
      end
      VSX_FORMAT: begin
        if (sub_extension == "zvlsseg") begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", add_nfields(get_instr_name(), 7),
                                                   vs3.name(), rs1.name(), vs2.name());
        end else begin
          asm_str = $sformatf("%0s %0s,(%0s),%0s", get_instr_name(),
                                                   vs3.name(), rs1.name(), vs2.name());
        end
      end
      default: begin
        `uvm_fatal(`gfn, $sformatf("Unsupported format %0s", format.name()))
      end
    endcase
    // Add vector mask
    asm_str = {asm_str, vec_vm_str()};
    if(comment != "") begin
      asm_str = {asm_str, " #",comment};
    end
    return asm_str.tolower();
  endfunction : convert2asm

  function void pre_randomize();
    super.pre_randomize();
    vs1.rand_mode(has_vs1);
    vs2.rand_mode(has_vs2);
    vs3.rand_mode(has_vs3);
    vd.rand_mode(has_vd);
    if (!(category inside {LOAD, STORE})) begin
      load_store_solve_order_c.constraint_mode(0);
    end
    if(instr_name inside {VLM_V, VSM_V}) begin
	  load_store_eew_emul_c.constraint_mode(0);   
    end
    if(check_sub_extension(sub_extension, "zvlsseg")) begin
	  if(instr_name inside {VLE_V, VSR_V}) begin
		nfields_c.constraint_mode(0);
	  end else begin
		nfields_whole_reg_c.constraint_mode(0);
	  end
    end else begin
	  nfields_c.constraint_mode(0);
	  nfields_whole_reg_c.constraint_mode(0);
	end
  endfunction : pre_randomize

  virtual function void set_rand_mode();
    string name = instr_name.name();
    has_rs1 = 1;
    has_rs2 = 0;
    has_rd  = 0;
    has_fs1 = 0;
    has_fs2 = 0;
    has_fs3 = 0;
    has_fd  = 0;
    has_imm = 0;
    if (sub_extension != "zvlsseg") begin
      nfields.rand_mode(0);
    end
    if ((name.substr(0, 1) == "VW") || (name.substr(0, 2) == "VFW")) begin
      is_widening_instr = 1'b1;
    end
    if (name.substr(0, 2) == "VQW") begin
      is_quad_widening_instr = 1'b1;
      is_widening_instr = 1'b1;
    end
    if ((name.substr(0, 1) == "VN") || (name.substr(0, 2) == "VFN")) begin
      is_narrowing_instr = 1'b1;
    end
    if (uvm_is_match("*CVT*", name)) begin
      is_convert_instr = 1'b1;
      has_vs1 = 1'b0;
    end
    if (allowed_va_variants.size() > 0) begin
      has_va_variant = 1;
    end
    // Set the rand mode based on the superset of all VA variants
    if (format == VA_FORMAT) begin
      has_imm = 1'b1;
      has_rs1 = 1'b1;
      has_fs1 = 1'b1;
    end
    if (format == VS2_FORMAT) begin
	  if (instr_name inside {VZEXT, VSEXT}) begin
	    has_vs1 = 1'b0;
	  end
    end
    if (instr_name inside {VPOPC_M, VFIRST_M, VMV_X_S}) begin
	   has_rd = 1'b1; 
    end
    if (instr_name == VFMV_F_S) begin
	   has_fd = 1'b1; 
    end
    if (instr_name inside {VLSE_V, VSSE_V, VLSSEGE_V, VSSSEGE_V}) begin
	  has_rs2 = 1'b1; 
	end
  endfunction : set_rand_mode

  virtual function string vec_vm_str();
    if (vm) begin
      return "";
    end else begin
      if (instr_name inside {VMERGE, VFMERGE, VADC, VSBC, VMADC, VMSBC}) begin
        return ",v0";
      end else begin
        return ",v0.t";
      end
    end
  endfunction

  function string add_nfields(string instr_name, int prefix_len);
	string prefix = instr_name.substr(0, prefix_len - 1);
    string suffix = instr_name.substr(prefix_len, instr_name.len() - 1);
    return $sformatf("%0s%0d%0s", prefix, nfields + 1, suffix);
  endfunction

  function string add_eew(string instr_name, string prefix);
    string suffix = instr_name.substr(prefix.len(), instr_name.len() - 1);
    return $sformatf("%0s%0d%0s", prefix,  eew, suffix);
  endfunction

  function bit check_sub_extension(string s, string literal);
    return s == literal;
  endfunction

endclass : riscv_vector_instr

class riscv_vset_instr extends riscv_instr;
  vtype_t vtype;
  bit [XLEN-1:0] vl;

  `uvm_object_utils(riscv_vector_instr)
  `uvm_object_new

  virtual function void set_rand_mode();
	 has_rd = 1'b0;	 
	 has_rs1 = 1'b0;
	 has_rs2 = 1'b0;
	 has_imm = 1'b0;
  endfunction
  
  function void pre_randomize();
	csr.rand_mode(0);
	// csr_c.constraint_mode(0);
  endfunction
  
  
  virtual function string convert2asm(string prefix = "");
    string asm_str;
	asm_str = {instr_name.name(), " ", rd.name()};
	case(instr_name)
      VSETIVLI: begin
	    asm_str = {asm_str, ", ", $sformatf("%0d", vl), ", ", vtype_str()};
      end
      VSETVLI: begin
	    asm_str = {asm_str, ", ", rs1.name(), ", ", vtype_str()};
      end
      VSETVL: begin
	    asm_str = {asm_str, ", ", rs1.name(), ", ", rs2.name()};
      end
	endcase
	if(comment != "") begin
      asm_str = {asm_str, " #",comment};
    end
    return asm_str.tolower();
  endfunction
  
  virtual function string vtype_str();
	  string lmul_str;
	  string vta_str;
	  string vma_str;
	  if ((vtype.vlmul > 1) && (vtype.fractional_lmul)) begin
        lmul_str = $sformatf("mf%0d", vtype.vlmul);
      end else begin
        lmul_str = $sformatf("m%0d", vtype.vlmul);
      end
      if(vtype.vta) begin
        vta_str = "ta";
      end else begin
	    vta_str = "tu";
      end
      if(vtype.vma) begin
        vma_str = "ma";
      end else begin
	    vma_str = "mu";
	  end
	  vtype_str = $sformatf("e%0d, %0s, %0s, %0s", vtype.vsew, lmul_str, vta_str, vma_str);
  endfunction
endclass
