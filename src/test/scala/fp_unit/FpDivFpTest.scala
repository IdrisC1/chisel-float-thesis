// package fp_unit

// import chisel3._
// import chiseltest._
// import chiseltest.simulator.VerilatorBackendAnnotation
// import org.scalatest.flatspec.AnyFlatSpec
// import org.scalatest.matchers.should.Matchers

// // Format-aware tests for the high-level FpDivFp module (uses FpUtils conversions)
// class FpDivFpTest extends AnyFlatSpec with Matchers with ChiselScalatestTester with FpUtils {
//   behavior of "FpDivFp"

//   val maxCyclesPerTest = 10000
//   val testNum = 200

//   def runDivTests[T <: Module](dutFactory: => T, genTests: Int, is64: Boolean = false)(run: T => Unit) = {
//     val timeout = if (is64) maxCyclesPerTest * 5 else maxCyclesPerTest
//     test(dutFactory).withAnnotations(Seq(VerilatorBackendAnnotation, WriteVcdAnnotation)) { dut =>
//       dut.clock.setTimeout(timeout)
//       run(dut)
//     }
//   }

//   it should "perform FP32 DIV correctly (format-aware wrapper)" in {
//     runDivTests(new FpDivFp(typeA = FP32, typeB = FP32, typeC = FP32), testNum, is64 = false) { dut =>
//       val rng = new scala.util.Random(42)
//       for (i <- 0 until testNum) {
//         // generate random non-NaN, non-INF floats
//         val a = java.lang.Float.intBitsToFloat(rng.nextInt() & 0x7fffffff)
//         var b = java.lang.Float.intBitsToFloat(rng.nextInt() & 0x7fffffff)
//         // val a = genRandomValue(FP32)
//         // val b = genRandomValue(FP32)
//         if (b == 0.0f) b = 1.0f

//         val expected = a/b
//         val aBits = floatToUInt(FP32, a)
//         val bBits = floatToUInt(FP32, b)
//         val expectedBits = floatToUInt(FP32, expected)

//         dut.io.in_a.poke(aBits.U)
//         dut.io.in_b.poke(bBits.U)
//         dut.io.rnd_mode.poke(0.U)    // adjust if different encoding needed
//         dut.io.tag_i.poke(0.U)
//         dut.io.in_valid.poke(true.B)
//         dut.io.out_ready.poke(true.B)

//         dut.clock.step(1)
//         dut.io.in_valid.poke(false.B)

//         var cycles = 0
//         while (!dut.io.out_valid.peek().litToBoolean && cycles < maxCyclesPerTest) {
//           dut.clock.step(1); cycles += 1
//         }

//         withClue(s"FP32 DIV test #$i a=$a b=$b took $cycles cycles: ") {
//           dut.io.out_valid.peek().litToBoolean shouldBe true
//           val got = dut.io.out.peek().litValue
//           got shouldBe expectedBits
//         }

//         dut.clock.step(1)
//       }
//     }
//   }

// //   it should "perform FP64 DIV correctly (format-aware wrapper, longer timeout)" in {
// //     runDivTests(new FpDivFp(typeA = FP64, typeB = FP64, typeC = FP64), testNum / 4, is64 = true) { dut =>
// //       val rng = new scala.util.Random(17)
// //       for (i <- 0 until (testNum / 4)) {
// //         var a = java.lang.Double.longBitsToDouble(rng.nextLong() & 0x7fffffffffffffffL).toFloat
// //         var b = java.lang.Double.longBitsToDouble(rng.nextLong() & 0x7fffffffffffffffL).toFloat
// //         if (b == 0.0f) b = 1.0f

// //         val expected = (a, dut.typeA) / (b, dut.typeB)
// //         val aBits = floatToUInt(dut.typeA, a)
// //         val bBits = floatToUInt(dut.typeB, b)
// //         val expectedBits = floatToUInt(dut.typeC, expected)

// //         dut.io.in_a.poke(aBits.U)
// //         dut.io.in_b.poke(bBits.U)
// //         dut.io.rnd_mode.poke(0.U)
// //         dut.io.tag_i.poke(0.U)
// //         dut.io.in_valid.poke(true.B)
// //         dut.io.out_ready.poke(true.B)

// //         dut.clock.step(1)
// //         dut.io.in_valid.poke(false.B)

// //         var cycles = 0
// //         while (!dut.io.out_valid.peek().litToBoolean && cycles < (maxCyclesPerTest * 4)) {
// //           dut.clock.step(1); cycles += 1
// //         }

// //         withClue(s"FP64 DIV test #$i took $cycles cycles: ") {
// //           dut.io.out_valid.peek().litToBoolean shouldBe true
// //           val got = dut.io.out.peek().litValue
// //           got shouldBe expectedBits
// //         }

// //         dut.clock.step(1)
// //       }
// //     }
// //   }
// }