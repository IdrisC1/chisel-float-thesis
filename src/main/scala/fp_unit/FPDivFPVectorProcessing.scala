
package fp_unit

import chisel3._
import chisel3.util.HasBlackBoxResource
import chisel3.experimental.RawParam
import chisel3.util._

/** BlackBox wrapper for fpnew_divsqrt_multiV2.sv */
class FpDivFpVectorProcessiongBlackBox(
    topmodule: String,
    typeX: FpType,
    // val FP_FORMAT: Int = 2,      // Default FP16, matches fpnew_pkg_snax::fp_format_e
    val NUM_PIPE_REGS: Int = 0,
    val PIPE_CONFIG: Int = 1,    // AFTER
    val TAG_WIDTH: Int = 1,
    // val WIDTH: Int = 16         // Matches input width for FP16
) extends BlackBox(
    Map(
    "FpFormat" -> RawParam(typeX.fpnewFormatEnum),
    "NumPipeRegs" -> NUM_PIPE_REGS,
    // "PipeConfig" -> PIPE_CONFIG, 
    // "PipeConfig" -> fpnew_pkg_snax::AFTER,
    // "TagType" -> "logic",
    "PRECISION_CTRL" -> RawParam("'h00")
)) with HasBlackBoxResource {

    val io = IO(new Bundle {
        val clk_i = Input(Clock())
        val rst_ni = Input(Bool())
        
        // Input signals
        // val operands_i = Input(Vec(2, UInt(typeX.width.W)))
        val operands_i = Input(UInt((2 * typeX.width).W))
        // val is_boxed_i = Input(Vec(6, Vec(2, Bool()))) // NUM_FORMATS=6 x 2 operands
        // val rnd_mode_i = Input(UInt(3.W))              // fpnew_pkg_snax::roundmode_e width
        val tag_i = Input(UInt(TAG_WIDTH.W))
        val mask_i = Input(Bool())
        val vectorial_op_i = Input(Bool())

        // Handshake signals
        val in_valid_i = Input(Bool())
        val in_ready_o = Output(Bool())
        val divsqrt_done_o = Output(Bool())
        val divsqrt_ready_o = Output(Bool())
        val simd_synch_done_i = Input(Bool())
        val simd_synch_rdy_i = Input(Bool())
        val flush_i = Input(Bool())

        // Output signals
        val result_o = Output(UInt(typeX.width.W))
        val status_o = Output(UInt(5.W))               // fpnew_pkg_snax::status_t width
        val extension_bit_o = Output(Bool())
        val tag_o = Output(UInt(TAG_WIDTH.W))
        val mask_o = Output(Bool())
        
        // Output handshake
        val out_valid_o = Output(Bool())
        val out_ready_i = Input(Bool())
        val busy_o = Output(Bool())

        // Register enable and early valid
        val reg_ena_i = Input(UInt((NUM_PIPE_REGS max 1).W))
        val early_out_valid_o = Output(Bool())
    })
    override def desiredName: String = "fpnew_divsqrt_multiV2"

    // Add all required SystemVerilog files in correct dependency order
    addResource("/common_block/fpnew_pkg_snax.sv")
    addResource("/common_block/fpnew_classifier.sv")
    addResource("/common_block/fpnew_rounding.sv")
    addResource("/common_block/lzc.sv")
    addResource("/common_block/registers.sv")
    
    // Division specific files
    addResource("/Division/defs_div_sqrt_mvp.sv")
    addResource("/Division/control_mvp.sv")
    addResource("/Division/preprocess_mvp.sv")
    addResource("/Division/nrbd_nrsc_mvp.sv")
    addResource("/Division/iteration_div_sqrt_mvp.sv")
    addResource("/Division/norm_div_sqrt_mvp.sv")
    addResource("/Division/div_sqrt_top_mvp.sv")
    
    // Main implementation
    addResource("fpnew_divsqrt_multiV2.sv")
}

/** High-level wrapper for DivSqrtBlackBox that uses DataType formats */
class FpDivFpVectorProcessiong(
    val typeX: FpType,    // Input A format
    val NUM_PIPE_REGS: Int = 0,
    val TAG_WIDTH: Int = 1,
    modulename: String = "fpnew_divsqrt_multiV2"
) extends Module 
    with RequireAsyncReset{

    // Get widths from DataTypes
    val WIDTH_X = typeX.width


    val io = IO(new Bundle {
        val in_a = Input(UInt(WIDTH_X.W))
        val in_b = Input(UInt(WIDTH_X.W))
        val rnd_mode = Input(UInt(3.W))
        val in_valid = Input(Bool())
        val out_ready = Input(Bool())
        val tag_i = Input(UInt(TAG_WIDTH.W))  // Add tag input
        
        val result = Output(UInt(WIDTH_X.W))
        val out_valid = Output(Bool())
        val busy = Output(Bool())
        val tag_o = Output(UInt(TAG_WIDTH.W))  // Add tag output
    })

    // // Convert DataType to fpnew_pkg_snax format encoding
    // def dataTypeToFpFormat(dt: DataType): Int = dt match {
    //     case FP32 => 0    // FP32
    //     case FP64 => 1    // FP64  
    //     case FP16 => 2    // FP16
    //     case FP16ALT => 3 // FP16ALT
    //     case _ => 2       // Default to FP16
    // }

    // Instantiate BlackBox
    val FpdivFpvector = Module(new FpDivFpVectorProcessiongBlackBox(
        modulename,
        typeX,
        NUM_PIPE_REGS,
        TAG_WIDTH = TAG_WIDTH
    ))

    // Connect clock and reset
    FpdivFpvector.io.clk_i := clock
    FpdivFpvector.io.rst_ni := !reset.asBool

    // Connect all required inputs including tag
    FpdivFpvector.io.tag_i := io.tag_i
    // divSqrt.io.operands_i(0) := io.in_a
    // divSqrt.io.operands_i(1) := io.in_b
    FpdivFpvector.io.operands_i := Cat( io.in_b, io.in_a)
    // divSqrt.io.rnd_mode_i := io.rnd_mode
    
    // Connect control signals
    FpdivFpvector.io.in_valid_i := io.in_valid
    FpdivFpvector.io.out_ready_i := io.out_ready
    FpdivFpvector.io.mask_i := false.B
    FpdivFpvector.io.vectorial_op_i := false.B
    FpdivFpvector.io.flush_i := false.B
    FpdivFpvector.io.simd_synch_done_i := false.B
    FpdivFpvector.io.simd_synch_rdy_i := false.B
    FpdivFpvector.io.reg_ena_i := 1.U
    
    // All formats considered boxed
    // divSqrt.io.is_boxed_i.foreach(_.foreach(_ := true.B))
    
    // Connect all outputs including tag
    io.result := FpdivFpvector.io.result_o
    io.out_valid := FpdivFpvector.io.out_valid_o
    io.busy := FpdivFpvector.io.busy_o
    io.tag_o := FpdivFpvector.io.tag_o
}

