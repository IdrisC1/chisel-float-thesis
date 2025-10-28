package fp_unit

import chisel3._
import chisel3.util._
// import chisel3.util.HasBlackBoxResource
// import chisel3.util.Fill

/** BlackBox for fpnew_divsqrt_multi.sv with explicit enum widths so they match fpnew_pkg typedefs */
class FpDivSqrtBlackBox(
  val WIDTH: Int = 64,
  val NUM_FORMATS: Int = 6,
  val ROUND_MODE_WIDTH: Int = 3,
  val OP_WIDTH: Int = 2,
  val FP_FORMAT_WIDTH: Int = 3,
  val STATUS_WIDTH: Int = 5,
  val TAG_WIDTH: Int = 8,
  val REG_ENA_WIDTH: Int = 1
) extends BlackBox(Map("FpFmtConfig" -> 1)) with HasBlackBoxResource {
  val io = IO(new Bundle {
    val clk_i    = Input(Clock())
    val rst_ni   = Input(Bool())

    val operands_i      = Input(Vec(2, UInt(WIDTH.W)))
    val is_boxed_i      = Input(UInt((NUM_FORMATS*2).W)) // conservative flattened representation
    val rnd_mode_i      = Input(UInt(ROUND_MODE_WIDTH.W))
    val op_i            = Input(UInt(OP_WIDTH.W))
    val dst_fmt_i       = Input(UInt(FP_FORMAT_WIDTH.W))
    val tag_i           = Input(UInt(TAG_WIDTH.W))
    val mask_i          = Input(Bool())
    val vectorial_op_i  = Input(Bool())

    val in_valid_i      = Input(Bool())
    val in_ready_o      = Output(Bool())
    val divsqrt_done_o  = Output(Bool())
    val simd_synch_done_i = Input(Bool())
    val divsqrt_ready_o = Output(Bool())
    val simd_synch_rdy_i = Input(Bool())
    val flush_i         = Input(Bool())

    val result_o        = Output(UInt(WIDTH.W))
    val status_o        = Output(UInt(STATUS_WIDTH.W))
    val extension_bit_o = Output(Bool())
    val tag_o           = Output(UInt(TAG_WIDTH.W))
    val mask_o          = Output(Bool())

    val out_valid_o     = Output(Bool())
    val out_ready_i     = Input(Bool())

    val busy_o          = Output(Bool())

    val reg_ena_i       = Input(UInt(REG_ENA_WIDTH.W))
    val early_out_valid_o = Output(Bool())
  })

  addResource("/fpnew_divsqrt_multi.sv")
  addResource("common_block/fpnew_pkg_snax.sv")
  addResource("common_block/fpnew_classifier.sv")
  addResource("common_block/fpnew_rounding.sv")
  addResource("common_block/lzc.sv")
  addResource("common_block/registers.sv")
 
}


/** Thin Module wrapper around BlackBox so chiseltest can instantiate a Module */
class FpDivSqrtWrapper(
  val WIDTH: Int = 64,
  val NUM_FORMATS: Int = 6,
  val ROUND_MODE_WIDTH: Int = 3,
  val OP_WIDTH: Int = 2,
  val FP_FORMAT_WIDTH: Int = 3,
  val STATUS_WIDTH: Int = 5,
  val TAG_WIDTH: Int = 8,
  val REG_ENA_WIDTH: Int = 1
) extends Module {
  val io = IO(new Bundle {
    val operands_i         = Input(Vec(2, UInt(WIDTH.W)))
    val is_boxed_i         = Input(UInt((NUM_FORMATS*2).W))
    val rnd_mode_i         = Input(UInt(ROUND_MODE_WIDTH.W))
    val op_i               = Input(UInt(OP_WIDTH.W))
    val dst_fmt_i          = Input(UInt(FP_FORMAT_WIDTH.W))
    val tag_i              = Input(UInt(TAG_WIDTH.W))
    val mask_i             = Input(Bool())
    val vectorial_op_i     = Input(Bool())

    val in_valid_i         = Input(Bool())
    val in_ready_o         = Output(Bool())
    val divsqrt_done_o     = Output(Bool())
    val simd_synch_done_i  = Input(Bool())
    val divsqrt_ready_o    = Output(Bool())
    val simd_synch_rdy_i   = Input(Bool())
    val flush_i            = Input(Bool())

    val result_o           = Output(UInt(WIDTH.W))
    val status_o           = Output(UInt(STATUS_WIDTH.W))
    val extension_bit_o    = Output(Bool())
    val tag_o              = Output(UInt(TAG_WIDTH.W))
    val mask_o             = Output(Bool())

    val out_valid_o        = Output(Bool())
    val out_ready_i        = Input(Bool())

    val busy_o             = Output(Bool())
    val reg_ena_i          = Input(UInt(REG_ENA_WIDTH.W))
    val early_out_valid_o  = Output(Bool())
  })

  val bb = Module(new FpDivSqrtBlackBox(
    WIDTH = WIDTH,
    NUM_FORMATS = NUM_FORMATS,
    ROUND_MODE_WIDTH = ROUND_MODE_WIDTH,
    OP_WIDTH = OP_WIDTH,
    FP_FORMAT_WIDTH = FP_FORMAT_WIDTH,
    STATUS_WIDTH = STATUS_WIDTH,
    TAG_WIDTH = TAG_WIDTH,
    REG_ENA_WIDTH = REG_ENA_WIDTH
  ))

  bb.io.clk_i := clock
  bb.io.rst_ni := reset

  bb.io.operands_i := io.operands_i
  bb.io.is_boxed_i := io.is_boxed_i
  bb.io.rnd_mode_i := io.rnd_mode_i
  bb.io.op_i := io.op_i
  bb.io.dst_fmt_i := io.dst_fmt_i
  bb.io.tag_i := io.tag_i
  bb.io.mask_i := io.mask_i
  bb.io.vectorial_op_i := io.vectorial_op_i

  bb.io.in_valid_i := io.in_valid_i
  io.in_ready_o := bb.io.in_ready_o
  io.divsqrt_done_o := bb.io.divsqrt_done_o
  bb.io.simd_synch_done_i := io.simd_synch_done_i
  io.divsqrt_ready_o := bb.io.divsqrt_ready_o
  bb.io.simd_synch_rdy_i := io.simd_synch_rdy_i
  bb.io.flush_i := io.flush_i

  io.result_o := bb.io.result_o
  io.status_o := bb.io.status_o
  io.extension_bit_o := bb.io.extension_bit_o
  io.tag_o := bb.io.tag_o
  io.mask_o := bb.io.mask_o

  io.out_valid_o := bb.io.out_valid_o
  bb.io.out_ready_i := io.out_ready_i

  io.busy_o := bb.io.busy_o
  bb.io.reg_ena_i := io.reg_ena_i
  io.early_out_valid_o := bb.io.early_out_valid_o
}



/** High-level, format-aware wrapper that exposes a simple API using your DataType enums and FpUtils */
class FpDivFp(
  val typeA: DataType,
  val typeB: DataType,
  val typeC: DataType,
  val wrapperWidth: Int = 64, // fixed bw used by divsqrt block
  val tagWidth: Int = 8
) extends Module {
  val inWidthA = typeA.width // DataType should expose width (bits)
  val inWidthB = typeB.width
  val outWidth = typeC.width

  val io = IO(new Bundle {
    val in_a      = Input(UInt(inWidthA.W))
    val in_b      = Input(UInt(inWidthB.W))
    val in_valid  = Input(Bool())
    val in_ready  = Output(Bool())

    val out_ready = Input(Bool())
    val out_valid = Output(Bool())
    val out       = Output(UInt(outWidth.W))

    val rnd_mode  = Input(UInt(3.W)) // match your fpnew roundmode width
    val tag_i     = Input(UInt(tagWidth.W))
    val tag_o     = Output(UInt(tagWidth.W))
  })

  // instantiate wrapper
  val divwb = Module(new FpDivSqrtWrapper(WIDTH = wrapperWidth, TAG_WIDTH = tagWidth))

  // zero-extend inputs to wrapper width
  def zextTo(u: UInt, target: Int): UInt = {
    if (u.getWidth == target) u else Cat(0.U((target - u.getWidth).W), u)
  }
  val op0 = zextTo(io.in_a, wrapperWidth)
  val op1 = zextTo(io.in_b, wrapperWidth)

  divwb.io.operands_i := VecInit(Seq(op0, op1))
  divwb.io.is_boxed_i := 0.U // not boxed by default, adjust if needed
  divwb.io.rnd_mode_i := io.rnd_mode
  divwb.io.op_i := 0.U // 0 => DIV. TODO: change for sqrt if needed
  // Map your Scala DataType to fpnew fp_format_e encoding:
  // TODO: implement formatToFpnewEncoding using your project's mapping (fpnew_pkg_snax)
  def formatToFpnewEncoding(dt: DataType): UInt = {
    // Example placeholder mapping, update to match fpnew_pkg_snax.sv:
    dt match {
      case FP32 => 0.U
      case FP64 => 1.U
      case FP16 => 2.U
      case BF16 => 3.U
      case _    => 0.U
    }
  }
  divwb.io.dst_fmt_i := formatToFpnewEncoding(typeC)
  divwb.io.tag_i := io.tag_i
  divwb.io.mask_i := false.B
  divwb.io.vectorial_op_i := false.B

  divwb.io.in_valid_i := io.in_valid
  io.in_ready := divwb.io.in_ready_o

  divwb.io.simd_synch_done_i := false.B
  divwb.io.simd_synch_rdy_i := false.B
  divwb.io.flush_i := false.B
  divwb.io.reg_ena_i := 1.U

  divwb.io.out_ready_i := io.out_ready

  io.out_valid := divwb.io.out_valid_o
  // result is wrapper-width; truncate to output width
  io.out := divwb.io.result_o(outWidth-1, 0)
  io.tag_o := divwb.io.tag_o
}