package fp_unit

import chisel3._
import chiseltest._
import chiseltest.simulator.VerilatorBackendAnnotation
import chiseltest.simulator.VcsBackendAnnotation
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable // Needed for the Queue
import coursier.core.Repository.Complete.Input.Ver

class FpDivFpTest extends AnyFlatSpec with Matchers with ChiselScalatestTester with FpUtils {
  behavior of "FpDivFp"

  val maxCyclesPerTest = 100
  val testNum = 100

  def runDivTests[T <: Module](dutFactory: => T)(run: T => Unit) = {
    test(dutFactory).withAnnotations(Seq(VerilatorBackendAnnotation, WriteVcdAnnotation)) { dut =>
      dut.clock.setTimeout(maxCyclesPerTest)
      dut.clock.step(10)
      run(dut)
    }
  }

  def testSingle(dut: FpDivFp, test_id: Int, a: Float, b: Float) = {
    val expected = a / b

    // println(expected)

    val aBits = floatToUInt(dut.typeX.asInstanceOf[FpType], a)
    val bBits = floatToUInt(dut.typeX.asInstanceOf[FpType], b)
    val expectedBits = floatToUInt(dut.typeX.asInstanceOf[FpType], expected)
    println(f"a : ${aBits.toLong.toBinaryString}, b:${bBits.toLong.toBinaryString}, expected:${expectedBits.toLong.toBinaryString}")
    dut.io.in_a.poke(aBits.U)
    dut.io.in_b.poke(bBits.U)
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
      println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${expected} ")
      println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${java.lang.Float.intBitsToFloat(got.toInt)}")
   
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
  // dut.io.rnd_mode.poke(0.U)
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
    println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${expected} ")
    println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${uintToDouble(dut.typeX.asInstanceOf[FpType],got)}") 
  
    got shouldBe expectedBits
    }
  
  dut.clock.step(1)
  }




def testPipelineStream(dut: FpDivFp, n: Int, TypeX: FpType) = {
    //Queue stores Double to accommodate both Float (FP32) and Double (FP64)
    // Format: (Expected Bits, Input A, Input B)
    val expectedQueue = mutable.Queue[(BigInt, Double, Double)]()

    println(f"--- Starting Pipeline Stream Test with $n Vectors for $TypeX ---")

    fork {
      // --- DRIVER THREAD ---
      for (i <- 0 until n) {
        
        // Use a match expression to generate values AND bits in one scope.
        // This calculates 'aBits', 'bBits', and 'expBits' and returns them to valid variables.
        val (aBits, bBits, expBits, aVal, bVal): (BigInt, BigInt, BigInt, Double, Double) = TypeX match  {
          case FP32 =>
            // FP32 Logic
            var a = getTrueRandomValue(TypeX) //genRandomValue(TypeX)
            var b = getTrueRandomValue(TypeX) //genRandomValue(TypeX)
            // if (b.abs < 1e-5) b = 1.0f
            println(f"Generated a = ${a}, b = ${b}") 
            
            val res = a / b
            // println(f"Result = ${res}")
            // Return tuple: (Bits A, Bits B, Bits Exp, Value A, Value B)
            (floatToUInt(FP32, a), floatToUInt(FP32, b), floatToUInt(FP32, res), a.toDouble, b.toDouble)

          case FP64 =>
            // FP64 Logic
            var a = genRandomValueDouble(TypeX)//(rng.nextDouble() - 0.5) * 200.0
            var b = genRandomValueDouble(TypeX)//(rng.nextDouble() - 0.5) * 200.0
            // if (b.abs < 1e-10) b = 1.0
            
            val res = a / b
            (doubleToUInt(FP64, a), doubleToUInt(FP64, b), doubleToUInt(FP64, res), a, b)
            
          case _ => throw new Exception("Unsupported FP Type")
        }

        // 3. Push to Queue (Using the Double values we extracted)
        expectedQueue.enqueue((expBits, aVal, bVal))

        // 4. Drive Signals (Now aBits/bBits are visible here!)
        dut.io.in_a.poke(aBits.U)
        dut.io.in_b.poke(bBits.U)
        dut.io.div_valid.poke(true.B)
        
        // 5. Advance 1 Cycle
        dut.clock.step(1)
      }
      dut.io.div_valid.poke(false.B)
      
    }.fork {
      // --- MONITOR THREAD ---
      for (i <- 0 until n) {
        while (!dut.io.out_done.peek().litToBoolean) {
          dut.clock.step(1)
        }

        val (expectedBits, a, b) = expectedQueue.dequeue()
        val got = dut.io.result.peek().litValue
        TypeX match{ 
          case FP32 =>
            withClue(f"Pipeline Fail at index $i: $a%f / $b%f") {
            // println(f"  a = 0x${aBits.toLong}%08X (${aBits.toLong.toBinaryString})")
            // println(f"  b = 0x${bBits.toLong}%08X (${bBits.toLong.toBinaryString})")
            println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${java.lang.Float.intBitsToFloat(expectedBits.toInt)} ")
            println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${java.lang.Float.intBitsToFloat(got.toInt)}")
            got shouldBe expectedBits
          }
          case FP64 => 
            withClue(f"Pipeline Fail at index $i: $a%f / $b%f") {
              println(f"  expected = 0x${expectedBits.toLong}%08X (${expectedBits.toLong.toBinaryString}), ${uintToDouble(dut.typeX.asInstanceOf[FpType],expectedBits)} ")
              println(f"  got      = 0x${got}%08X (${got.toLong.toBinaryString}), ${uintToDouble(dut.typeX.asInstanceOf[FpType],got)}")
              got shouldBe expectedBits
            }
        }
        dut.clock.step(1)
      }
    }.join()
    
    println("--- Pipeline Stream Test Passed ---")
  }


  def testSpecialCasesFP32(dut: FpDivFp) = {
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

  def testSpecialCasesFP64(dut: FpDivFp) = {
    val specialCases = Seq(             
      (0.0, 0.0),                                         // Zero / Zero = NaN
      (0.0, 1.0),                                         // Zero / Normal = Zero
      (1.0, 0.0),                                         // Normal / Zero = Infinity
      (Double.NaN, 1.0),                                  // NaN cases
      (1.0, Double.NaN),
      (Double.NaN, Double.NaN),
      (Double.PositiveInfinity, 1.0),                     // Infinity cases
      (1.0, Double.PositiveInfinity),
      (Double.NegativeInfinity, 1.0),
      (1.0, Double.NegativeInfinity),
      (Double.PositiveInfinity, Double.NegativeInfinity), // +inf / -inf = NaN
      (Double.NegativeInfinity, Double.PositiveInfinity), // -inf / +inf = NaN
      (Double.MinPositiveValue, Double.MinPositiveValue), // Smallest positive (Subnormal handling)
      (Double.MinPositiveValue, 0.0),
      (0.0, Double.MinPositiveValue)
    )

    specialCases.zipWithIndex.foreach { case ((a, b), index) => 
      // Ensure testSingle is updated to accept Double arguments
      testSingleDouble(dut, index + 1, a, b) 
    }
  }


  //---------------------Test Cases ---------------------//
  val numRandomTests = 100

  // it should "handle Special Cases " in {
  //   runDivTests(new FpDivFp(typeX = FP32)) { dut =>
  //     val specialCases = Seq(            
  //       (0.0f, 0.0f), (0.0f, 1.0f), (1.0f, 0.0f), 
  //       (Float.NaN, 1.0f), (1.0f, Float.NaN), (Float.PositiveInfinity, 1.0f)
  //     )
      
  //     specialCases.zipWithIndex.foreach { case ((a, b), index) => 
  //       testSingle(dut, index, a, b) 
  //     }
  //   }
  // }

it should "perform FP32 Randomized Pipeline Test" in {
    runDivTests(new FpDivFp(typeX = FP32)) { dut =>
      testPipelineStream(dut, numRandomTests, FP32)
    }
  }

  it should "perform FP64 Randomized Pipeline Test" in {
    runDivTests(new FpDivFp(typeX = FP64)) { dut =>
      testPipelineStream(dut, numRandomTests, FP64)
    }
  }


  it should "perform FP32 DIV correctly" in {
    runDivTests(new FpDivFp(typeX = FP32)) { dut =>
    //   val rng = new scala.util.Random(42)
      // for (i <- 0 until testNum) {
        // val a = genRandomValue(FP32)
        // var b = genRandomValue(FP32)
        // if (b == 0.0f) b = 1.0f  // Avoid division by zero
        val a = -2.1333084E-35.toFloat//2.2392744E-32.toFloat//-9.743106E-8.toFloat//1.1375.toFloat //-0.4690.toFloat // 3.4010.toFloat //7.845031 //851494.625000 //-9.743106E-8 // 2.1241657E-16
        val b = -1.0374664E-8.toFloat//1.699444E-17.toFloat//1.419752E-39.toFloat //5.6700.toFloat //3.2679.toFloat  //7.0076.toFloat //0.69879055 //0.000000    //1.419752E-39//3.4810254E19               5.8707 / -1.2212 gives problem if you add zero to the end
        // println(f"Testing a = ${a}, b = ${b}") -2.1333084E-35, b = -1.0374664E-8
        testSingle (dut, 1, a, b)
      //   testSingle(dut, i + 1, a, b)
      // }
    }
  }


  it should "perform FP64 DIV correctly" in {
    runDivTests(new FpDivFp(typeX = FP64)) { dut =>
      // val rng = new scala.util.Random(17)
      // for (i <- 0 until (testNum)) {
      //   val a = genRandomValueDouble(FP64)
      //   var b = genRandomValueDouble(FP64)
      //   if (b == 0.0f) b = 1.0f
        var a = 109.277647.toDouble//-38.17727047555721.toDouble//10.toDouble
        var b = -61.722065.toDouble//118.95835705484598.toDouble//5.toDouble
        testSingleDouble(dut, 1, a, b)

      //   testSingleDouble(dut, i+ 1, a, b)
      // }
    }
  }

  // it should "handle special cases for FP32 division" in {
  //   runDivTests(new FpDivFp(typeX = FP32)) { dut =>
  //     testSpecialCasesFP32(dut)
  //   }
  // }

  // it should "handle special cases for FP64 division" in {
  //   runDivTests(new FpDivFp(typeX = FP64)) { dut =>
  //     testSpecialCasesFP64(dut)
  //   }
  // }

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






