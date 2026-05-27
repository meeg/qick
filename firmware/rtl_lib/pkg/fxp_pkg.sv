package fxp_pkg;
  typedef struct packed  {
    bit sign;
    int unsigned nb;
    int unsigned nf;
  } repr_t;

  typedef enum {SUM, MULT} fxp_op_t;

  function automatic repr_t get_repr(input repr_t val1, input repr_t val2, input fxp_op_t op);
    case (op)
      SUM: begin
        return '{
          sign: val1.sign | val2.sign,
          nb: (val1.nb > val2.nb ? val1.nb : val2.nb) + 1 + 32'({(val1.sign^val2.sign)}),
          nf: val1.nf > val2.nf ? val1.nf : val2.nf
        };
      end
      MULT: begin
        return '{
          sign: val1.sign | val2.sign,
          nb: val1.nb + val2.nb + 32'({(val1.sign^val2.sign)}),
          nf: val1.nf + val2.nf
        };
      end
      default: begin
        $fatal(1, "Invalid operation");
        return '{default:0};
      end
    endcase
  endfunction

  // =========================================================================
  // Generic fixed-point conversion functions
  // These work with ANY bit width - no parameters needed
  // =========================================================================

  // Convert float to fixed-point (generic version)
  function automatic longint float_to_fixed(
    input real value,
    input int  nb,    // Number of bits (total)
    input int  frac   // Number of fractional bits
  );
    return $rtoi(value * (2.0 ** frac));
  endfunction

  // Convert fixed-point to float (generic version)
  function automatic real fixed_to_float(
    input longint value,  // Use longint to support up to 64 bits
    input int nb,         // Number of bits (total)
    input int frac        // Number of fractional bits
  );
    // Sign-extend if necessary
    longint signed svalue = value;
    if (nb < 64) begin
      // Sign-extend from nb bits to 64 bits
      if (value[nb-1]) begin  // If sign bit is 1
        svalue = value | (~((longint'(1) << nb) - 1));
      end
    end
    return real'(svalue) / (2.0 ** frac);
  endfunction

  // =========================================================================
  // Commonly used wrappers (you can customize these per project)
  // =========================================================================

  // Convert float to 16-bit signal with 13 fractional bits
  function automatic logic signed [15:0] float_to_signal(real value);
    return float_to_fixed(value, 16, 13);
  endfunction

  // Convert float to 32-bit gain with 16 fractional bits
  function automatic logic signed [31:0] float_to_gain(real value);
    return float_to_fixed(value, 32, 16);
  endfunction

  // Convert 16-bit signal to float
  function automatic real signal_to_float(logic signed [15:0] value);
    return fixed_to_float(value, 16, 13);
  endfunction

  // Convert 32-bit gain to float
  function automatic real gain_to_float(logic signed [31:0] value);
    return fixed_to_float(value, 32, 16);
  endfunction

  // =========================================================================
  // Helper functions for testing
  // =========================================================================

  // Compare two fixed-point values with tolerance
  function automatic bit compare_fixed(
    input longint actual,
    input longint expected,
    input int nb,
    input int frac,
    input real tolerance = 0.01
  );
    real act_float = fixed_to_float(actual, nb, frac);
    real exp_float = fixed_to_float(expected, nb, frac);
    real diff = (act_float - exp_float);
    if (diff < 0) diff = -diff;
    return (diff <= tolerance);
  endfunction

  // Pretty print fixed-point value
  function automatic string fixed_to_string(
    input longint value,
    input int nb,
    input int frac
  );
    real val = fixed_to_float(value, nb, frac);
    return $sformatf("%0.4f (0x%h)", val, value);
  endfunction

  // Display formatted fixed-point value
  function automatic void display_fixed(
    input string label,
    input longint value,
    input int nb,
    input int frac
  );
    $display("%s: %s", label, fixed_to_string(value, nb, frac));
  endfunction

  // =========================================================================
  // Additional utility functions
  // =========================================================================

  // Saturate a value to specific bit width
  function automatic longint saturate(
    input longint value,
    input int nb
  );
    longint signed max_val = (longint'(1) << (nb-1)) - 1;
    longint signed min_val = -(longint'(1) << (nb-1));

    if (value > max_val)
      return max_val;
    else if (value < min_val)
      return min_val;
    else
      return value;
  endfunction

  // Calculate fixed-point error between two values
  function automatic real calculate_error(
    input longint actual,
    input longint expected,
    input int nb,
    input int frac
  );
    real act = fixed_to_float(actual, nb, frac);
    real exp = fixed_to_float(expected, nb, frac);
    return act - exp;
  endfunction

endpackage
