import * as util from "util";

/*
Note: without via_ir and using 0.8.17, changes that should reduce gas use increase it instead. Noting them down for later use:
* unsafe cast uint known to be on 1 bit to bool (instead of using i>0 casting)
* unsafe cast uint to address (instead of address(uint160(u)) when u is already safe
*/

export const preamble = `/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */`;

export const struct_utilities = `/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly ("memory-safe") { u := b }
}
import "@mgv/lib/core/Constants.sol";`;

const field_var = (_name: string, prop: string) => {
  return `${_name}_${prop}`;
};

type field_def = { name: string; type: string; underlyingType?: string; bits: number };

type struct_def = {
  fields: field_def[],
  additionalDefinitions?: string | ((Struct) => string)
}

const base_types = ["int", "uint", "address", "bool"];

const capitalize = (s: string) => s.slice(0, 1).toUpperCase() + s.slice(1);

class Field {
  name: string;
  // user-facing type
  type: string;
  userDefined: boolean;
  // underlyingType if there is one, type otherwise
  rawType: string;
  bits: number;
  vars: { before: string; mask: string; bits: string; mask_inv: string; cast_mask: string; size_error:string;};
  mask: string;
  cast_mask: string;
  mask_inv: string | undefined;

  constructor(data: field_def) {
    Field.validate(data);
    this.name = data.name;
    this.type = data.type;
    this.userDefined = !!data.underlyingType;
    this.rawType = data.underlyingType ?? this.type;
    this.bits = data.bits;
    this.vars = {
      before: field_var(this.name, "before"),
      mask: field_var(this.name, "mask"),
      cast_mask: field_var(this.name, "cast_mask"),
      mask_inv: field_var(this.name, "mask_inv"),
      size_error: field_var(this.name, "size_error"),
      bits: field_var(this.name, "bits"),
    };
    // focus-mask: 1s at field location, 0s elsewhere
    this.mask_inv = `(ONES << 256 - ${this.vars.bits}) >> ${this.vars.before}`;
    // cleanup-mask: 0s at field location, 1s elsewhere
    this.mask = `~${this.vars.mask_inv}`;
    // cast-mask: 0s followed by |field| trailing 1s
    this.cast_mask = `~(ONES << ${this.vars.bits})`;

  }

  static validate(data:field_def) {
    const desc = util.inspect(data);

    if (!base_types.includes(data.type)) {
      if (data.underlyingType && !base_types.includes(data.underlyingType)) {
      throw new Error(
        `bad underlying type in ${desc}, only allowed types are uint,int,address, and bool.`
      );
      } else if (!data.underlyingType) {
        throw new Error(
          `bad type ${desc}, only allowed types are uint,int,address, bool and user-defined types`
        );
      }
    }
    if (data.type === "address" && data.bits !== 160) {
      throw new Error(`bad field ${desc}, addresses must have 160 bits`);
    }
  }

  extract(from: string) {
    let val;
    if (this.rawType === "bool") {
      val = `(${from} & ${this.vars.mask_inv})`;
    } else {
      // must cast to int so right-shift is correct for negative ints
      const cast = this.rawType === "int" ? "int" : "uint";
      val = `${cast}(${from} << ${this.vars.before}) >> (256 - ${this.vars.bits})`;
    }
    return this.from_base(val);
  }

  from_base(uint_val: string) {
    let raw;
    if (this.rawType === "address") {
      raw = `address(uint160(${uint_val}))`;
    } else if (this.rawType === "bool") {
      raw = `(${uint_val} > 0)`;
    } else if (this.rawType === "int") {
      raw = `int(${uint_val})`;
    } else {
      // uint by default
      raw = uint_val;
    }
    // if user-defined type, then wrap
    if (this.userDefined) {
      return `${this.type}.wrap(${raw})`;
    } else {
      return raw;
    }
  }

  inject(val: string) {
    const uint_val = this.to_base(val);
    return `(${uint_val} << (256 - ${this.vars.bits})) >> ${this.vars.before}`;
  }

  to_base(val: string) {
    if (this.userDefined) {
      val = `${this.type}.unwrap(${val})`;
    }
    if (this.rawType === "address") {
      return `uint(uint160(${val}))`;
    } else if (this.rawType === "bool") {
      return `uint_of_bool(${val})`;
    } else if (this.rawType === "int") {
      // cast to uint so later rightshift creates 0s to the left
      return `uint(${val})`;
    } else {
      // uint by default
      return val;
    }
  }

  unwrapped(wrapped:string) {
    // console.log(this,"for",wrapped);
    let unwrapped = wrapped;
    if (this.userDefined) {
      unwrapped = `${this.type}.unwrap(${unwrapped})`;
    }
    return unwrapped;
  }
}

class Struct {
  // validate struct_def: correct types & sizes
  static validate(fields_def: field_def[]) {
    const red = (acc: number, field: field_def) => acc + field.bits;
    const bits = fields_def.reduce(red, 0);
    if (bits > 256) {
      throw new Error(
        `bad fields ${util.inspect(fields_def)}\nbitsize ${bits} > 256`
      );
    }
  }

  name: string;
  Name: string;
  Lib: string;
  Packed: string;
  Unpacked: string;
  filenames: { src: string; test: string };
  fields: Field[];
  additionalDefinitions?: string;

  constructor(
    name: string,
    struct_def: struct_def,
    filenamers: (_: Struct) => Struct["filenames"]
  ) {
    Struct.validate(struct_def.fields);
    this.name = name;
    this.Name = capitalize(this.name);
    this.Packed = `${this.Name}`;
    this.Lib = `${this.Name}Lib`;
    this.Unpacked = `${this.Name}Unpacked`;
    this.filenames = filenamers(this);
    this.fields = struct_def.fields.map((data: field_def) => new Field(data));
    if (typeof struct_def.additionalDefinitions === "string") {
      this.additionalDefinitions = struct_def.additionalDefinitions;
    } else if (struct_def.additionalDefinitions) {
      this.additionalDefinitions = struct_def.additionalDefinitions(this);
    }
  }
  get(field_name:string) {
    const index = this.fields.findIndex(f => f.name === field_name);
    if (index === -1) {
      throw new Error(`Field ${field_name} not found in struct ${this}`);
    }
    return this.fields[index];
  }
  unwrap(val: any) {
    return `${this.Packed}.unwrap(${val})`;
  }
  wrap(val: any) {
    return `${this.Packed}.wrap(${val})`;
  }
}

export const make_structs = (
  struct_defs: { [key: string]: struct_def },
  filenamer: (_: Struct) => Struct["filenames"]
) => {
  return Object.entries(struct_defs).map(([name, struct_def]) => {
    return new Struct(name, struct_def, filenamer);
  });
};
