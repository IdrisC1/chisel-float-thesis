package fp_unit

import chisel3._
import chiseltest._
import chiseltest.simulator.VerilatorBackendAnnotation
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class DivSqrtFpTest extends AnyFlatSpec with Matchers with ChiselScalatestTester with FpUtils {
  behavior of "FpDivFp"

  val maxCyclesPerTest = 10000
  val testNum = 200

  def runDivTests[T <: Module](dutFactory: => T, genTests: Int, is64: Boolean = false)(run: T => Unit) = {
    val timeout = if (is64) maxCyclesPerTest * 5 else maxCyclesPerTest
    test(dutFactory).withAnnotations(Seq(VcsBackendAnnotation, WriteVcdAnnotation)) { dut =>
      dut.clock.setTimeout(timeout)
      run(dut)
    }
  }

  def testSingle(dut: FpDivFp, test_id: Int, a: Float, b: Float) = {
    val expected = a / b
    println(expected)
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

        println(f"  a = 0x${aBits.toLong}%08X (${aBits.toLong.toBinaryString})")
      println(f"  b = 0x${bBits.toLong}%08X (${bBits.toLong.toBinaryString})")
      println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${expected} ")
      println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${java.lang.Float.intBitsToFloat(got.toInt)}")
   

      got shouldBe expectedBits
       // Print results in readable format
        }
    

   

    dut.clock.step(1)
  }

  def testSpecialCases(dut: FpDivFp) = {
    val specialCases = Seq(
      (1.0f, 2.0f),           // Basic division
      (0.0f, 1.0f),           // Zero numerator
      (Float.MaxValue, 2.0f),  // Large numerator
      (1.0f, Float.MinPositiveValue), // Small denominator
      (Float.MinPositiveValue, 1.0f)  // Small numerator
    )

    specialCases.zipWithIndex.foreach { case ((a, b), index) => 
      testSingle(dut, index + 1, a, b) 
    }
  }

  it should "perform FP32 DIV correctly" in {
    runDivTests(new FpDivFp(typeX = FP32), testNum, is64 = false) { dut =>
    //   val rng = new scala.util.Random(42)
      for (i <- 0 until testNum) {
        var a = genRandomValue(FP32)
        var b = genRandomValue(FP32)
        if (b == 0.0f) b = 1.0f  // Avoid division by zero
        // var a = 10.toFloat
        // var b = 5.toFloat
        testSingle(dut, i + 1, a, b)
      }
    }
  }

//   it should "perform FP64 DIV correctly" in {
//     runDivTests(new DivSqrtFp(typeA = FP64, typeB = FP64, typeC = FP64), testNum / 4, is64 = true) { dut =>
//       val rng = new scala.util.Random(17)
//       for (i <- 0 until (testNum / 4)) {
//         var a = genRandomValue(FP64).toFloat
//         var b = genRandomValue(FP64).toFloat
//         if (b == 0.0f) b = 1.0f
//         testSingle(dut, i + 1, a, b)
//       }
//     }
//   }

//   it should "handle special cases for FP32 division" in {
//     runDivTests(new DivSqrtFp(typeA = FP32, typeB = FP32, typeC = FP32), 1, is64 = false) { dut =>
//       testSpecialCases(dut)
//     }
//   }

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

