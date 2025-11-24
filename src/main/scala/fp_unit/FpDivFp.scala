
package fp_unit

import chisel3._
import chisel3.util.HasBlackBoxResource
import chisel3.experimental.RawParam
// import chisel3.util._

/** BlackBox wrapper for fpnew_divsqrt_multiV2.sv */
class FpDivFpBlackBox(
    topmodule: String,
    typeX: FpType,
    // val FP_FORMAT: Int = 2,      // Default FP16, matches fpnew_pkg_snax::fp_format_e
    // val NUM_PIPE_REGS: Int = 0,
    // val PIPE_CONFIG: Int = 1,    // AFTER
    // val TAG_WIDTH: Int = 1,
    // val WIDTH: Int = 16         // Matches input width for FP16
) extends BlackBox(
    Map(
    "FpFormat" -> RawParam(typeX.fpnewFormatEnum),
    // "NumPipeRegs" -> NUM_PIPE_REGS,
    // "PipeConfig" -> PIPE_CONFIG, 
    // "PipeConfig" -> fpnew_pkg_snax::AFTER,
    // "TagType" -> "logic",
    "PRECISION_CTRL" -> RawParam("'h00"),
    "Iteration_unit_num_S" -> RawParam("3111") // Use four units
    // "RM_SI"       -> RawParam("'h0")
)) with HasBlackBoxResource {

    val io = IO(new Bundle {
        val clk_i = Input(Clock())
        val rst_ni = Input(Bool())
        val div_valid    = Input(Bool())
        // Input signals
        // val operands_i = Input(Vec(2, UInt(typeX.width.W)))
        val operand_a_DI = Input(UInt(typeX.W))
        val operand_b_DI = Input(UInt(typeX.W))
        
        // val rnd_mode_i = Input(UInt(3.W))              // fpnew_pkg_snax::roundmode_e width
        val Kill_SI = Input(Bool())
        val result_DO = Output(UInt(typeX.W))
        val unit_status= Output(UInt(5.W))
        val unit_ready = Output(Bool())
        val unit_done = Output(Bool())
        
    })
    override def desiredName: String = "fp_div"

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
    addResource("fp_div.sv")
}

/** High-level wrapper for DivSqrtBlackBox that uses DataType formats */
class FpDivFp(
    val typeX: FpType,    // Input A format
    // val NUM_PIPE_REGS: Int = 0,
    // val TAG_WIDTH: Int = 1,
    modulename: String = "fp_div"
) extends Module 
    with RequireAsyncReset{

    val io = IO(new Bundle {
        val in_a = Input(UInt(typeX.W))
        val in_b = Input(UInt(typeX.W))
        // val rnd_mode = Input(UInt(3.W))
        val div_valid = Input(Bool())

        val out_done = Output(Bool())
        
        val result = Output(UInt(typeX.W))
        // val out_valid = Output(Bool())
        // val busy = Output(Bool())
        val status = Output(UInt(5.W))
     
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
    val fpdivfp = Module(new FpDivFpBlackBox(
        modulename,
        typeX
    ))


    fpdivfp.io.clk_i := clock
    fpdivfp.io.rst_ni := !reset.asBool


    fpdivfp.io.operand_a_DI := io.in_a
    fpdivfp.io.operand_b_DI := io.in_b
 
    // Connect control signals
    fpdivfp.io.div_valid := io.div_valid
    fpdivfp.io.Kill_SI := false.B
    

    // Connect all outputs including tag
    io.result := fpdivfp.io.result_DO
    // io.out_valid := fpdivfp.io.unit_ready
    io.status := fpdivfp.io.unit_status
    io.out_done:= fpdivfp.io.unit_done
    // io.busy := fpdivfp.io.busy_o
 
}


object FpDivFpEmitter extends App {
  emitVerilog(
    new FpDivFp(typeX = FP64),
    Array("--target-dir", "generated/fp_unit")
  )
}