package fp_unit

import chisel3._
import chiseltest._
// import chiseltest.simulator.VerilatorBackendAnnotation
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class FpDivFpTest extends AnyFlatSpec with Matchers with ChiselScalatestTester with FpUtils {
  behavior of "FpDivFp"

  val maxCyclesPerTest = 10000
  val testNum = 200

  def runDivTests[T <: Module](dutFactory: => T)(run: T => Unit) = {
    //, is64: Boolean = false
    // val timeout = if (is64) maxCyclesPerTest * 5 else maxCyclesPerTest
    test(dutFactory).withAnnotations(Seq(VcsBackendAnnotation, WriteVcdAnnotation)) { dut =>
      dut.clock.setTimeout(maxCyclesPerTest)
      run(dut)
    }
  }

  def testSingle(dut: FpDivFp, test_id: Int, a: Float, b: Float) = {
    val expected = a / b

    // println(expected)

    val aBits = floatToUInt(dut.typeX.asInstanceOf[FpType], a)
    val bBits = floatToUInt(dut.typeX.asInstanceOf[FpType], b)
    val expectedBits = floatToUInt(dut.typeX.asInstanceOf[FpType], expected)

    dut.io.in_a.poke(aBits.U)
    dut.io.in_b.poke(bBits.U)
    // dut.io.operands_0(0).poke(aBits.U)
    // dut.io.operands_i(1).poke(bBits.U)
    dut.io.rnd_mode.poke(0.U)
    dut.io.div_valid.poke(true.B)
    
    // dut.io.out_ready.poke(true.B)
    dut.clock.step(1)
    dut.io.div_valid.poke(false.B)
    
    var cycles = 0
    while (!dut.io.out_done.peek().litToBoolean && cycles < maxCyclesPerTest) {
      dut.clock.step(1)
      cycles += 1
    }

    withClue(s"Test #$test_id a=$a b=$b took $cycles cycles: ") {
      dut.io.out_done.peek().litToBoolean shouldBe true
      val got = dut.io.result.peek().litValue

      println(f"Number of cycles: ${cycles}")
      // println(f"  a = 0x${aBits.toLong}%08X (${aBits.toLong.toBinaryString})")
      // println(f"  b = 0x${bBits.toLong}%08X (${bBits.toLong.toBinaryString})")
      // println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${expected} ")
      // println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${java.lang.Float.intBitsToFloat(got.toInt)}")
   
      got shouldBe expectedBits
       // Print results in readable format
      }
    
    dut.clock.step(1)
  }

  def testSingleDouble(dut: FpDivFp, test_id: Int, a: Double, b: Double) = {
  val expected = a / b

  // println(expected)
  val aBits = doubleToUInt(dut.typeX.asInstanceOf[FpType], a)
  val bBits = doubleToUInt(dut.typeX.asInstanceOf[FpType], b)
  val expectedBits = doubleToUInt(dut.typeX.asInstanceOf[FpType], expected)

  dut.io.in_a.poke(aBits.U)
  dut.io.in_b.poke(bBits.U)
  // dut.io.operands_0(0).poke(aBits.U)
  // dut.io.operands_i(1).poke(bBits.U)
  dut.io.rnd_mode.poke(0.U)
  dut.io.div_valid.poke(true.B)
  
  // dut.io.out_ready.poke(true.B)
  dut.clock.step(1)
  dut.io.div_valid.poke(false.B)
  
  var cycles = 0
  while (!dut.io.out_done.peek().litToBoolean && cycles < maxCyclesPerTest) {
    dut.clock.step(1)
    cycles += 1
  }

  withClue(s"Test #$test_id a=$a b=$b took $cycles cycles: ") {
    dut.io.out_done.peek().litToBoolean shouldBe true
    val got = dut.io.result.peek().litValue

    println(f"Number of cycles: ${cycles}")
    // println(f"  a = 0x${aBits.toLong}%08X (${aBits.toLong.toBinaryString}), ${a}")
    // println(f"  b = 0x${bBits.toLong}%08X (${bBits.toLong.toBinaryString}), ${b}")
    // println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${expected} ")
    // println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${uintToDouble(dut.typeX.asInstanceOf[FpType],got)}") 
  
    got shouldBe expectedBits
    }
  
  dut.clock.step(1)
  }





  def testSpecialCases(dut: FpDivFp) = {
    val specialCases = Seq(            
      (0.0f, 0.0f),                                     // Zero cases
      (0.0f, 1.0f),
      (1.0f, 0.0f),                                     // Division by zero
      (Float.NaN, 1.0f),                                // NaN cases
      (1.0f, Float.NaN),
      (Float.NaN, Float.NaN),
      (Float.PositiveInfinity, 1.0f),                   // Infinity cases
      (1.0f, Float.PositiveInfinity),
      (Float.NegativeInfinity, 1.0f),
      (1.0f, Float.NegativeInfinity),
      (Float.PositiveInfinity, Float.NegativeInfinity), // +inf + -inf = NaN
      (Float.NegativeInfinity, Float.PositiveInfinity), // -inf + +inf = NaN
      (Float.MinPositiveValue, Float.MinPositiveValue), // Smallest positive
      (Float.MinPositiveValue, 0.0f),
      (0.0f, Float.MinPositiveValue)
    )

    specialCases.zipWithIndex.foreach { case ((a, b), index) => 
      testSingle(dut, index + 1, a, b) 
    }
  }

  // it should "perform FP32 DIV correctly" in {
  //   runDivTests(new FpDivFp(typeX = FP32)) { dut =>
  //   //   val rng = new scala.util.Random(42)
  //     for (i <- 0 until testNum) {
  //       val a = genRandomValue(FP32)
  //       var b = genRandomValue(FP32)
  //       if (b == 0.0f) b = 1.0f  // Avoid division by zero
  //       // var a = 10.toFloat
  //       // var b = 5.toFloat
  //       testSingle(dut, i + 1, a, b)
  //     }
  //   }
  // }

  // it should "perform FP64 DIV correctly" in {
  //   runDivTests(new FpDivFp(typeX = FP64)) { dut =>
  //     // val rng = new scala.util.Random(17)
  //     for (i <- 0 until (testNum / 4)) {
  //       val a = genRandomValueDouble(FP64)
  //       var b = genRandomValueDouble(FP64)
  //       if (b == 0.0f) b = 1.0f
  //       // var a = 1.toDouble
  //       // var b = 0.toDouble
  //       testSingleDouble(dut, i + 1, a, b)
  //     }
  //   }
  // }

  it should "handle special cases for FP32 division" in {
    runDivTests(new FpDivFp(typeX = FP32)) { dut =>
      testSpecialCases(dut)
    }
  }

//   it should "perform FP16 DIV correctly" in {
//     runDivTests(new DivSqrtFp(typeA = FP16, typeB = FP16, typeC = FP16), testNum, is64 = false) { dut =>
//       val rng = new scala.util.Random(42)
//       for (i <- 0 until testNum) {
//         var a = genRandomValue(FP16)
//         var b = genRandomValue(FP16)
//         if (b == 0.0f) b = 1.0f
//         testSingle(dut, i + 1, a, b)
//       }
//     }
//   }

//   it should "perform FP16 DIV with FP32 output correctly" in {
//     runDivTests(new DivSqrtFp(typeA = FP16, typeB = FP16, typeC = FP32), testNum, is64 = false) { dut =>
//       val rng = new scala.util.Random(42)
//       for (i <- 0 until testNum) {
//         var a = genRandomValue(FP16)
//         var b = genRandomValue(FP16)
//         if (b == 0.0f) b = 1.0f
//         testSingle(dut, i + 1, a, b)
//       }
//     }
//   }
}

