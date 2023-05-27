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
  assembly { u := b }
}

uint constant ONES = type(uint).max;`;

const field_var = (_name:string, prop:string) => {
  return `${_name}_${prop}`;
};

type field_def = { name: string; type: string; bits: number; };

const capitalize = (s:string) => s.slice(0, 1).toUpperCase() + s.slice(1);

class Field {
  name: string;
  type: string;
  bits: number;
  vars: { before: string; mask: string; bits: string; mask_inv: string; }
  mask: string;
  mask_inv: string | undefined;

  constructor(data: field_def) {
    this.name = data.name;
    this.type = data.type;
    this.bits = data.bits;
    this.vars = {
      before: field_var(this.name, "before"),
      mask: field_var(this.name, "mask"),
      mask_inv: field_var(this.name, "mask_inv"),
      bits: field_var(this.name, "bits"),
    };
    // focus-mask: 1s at field location, 0s elsewhere
    this.mask_inv = `(ONES << 256 - ${this.vars.bits}) >> ${this.vars.before}`;
    // cleanup-mask: 0s at field location, 1s elsewhere
    this.mask = `~${this.vars.mask_inv}`;
  }

  extract(from: string) {
    let uint_val;
    if (this.type === "bool") {
      uint_val = `(${from} & ${this.vars.mask_inv})`;
    } else {
      uint_val = `(${from} & ${this.vars.mask_inv}) >> (256 - ${this.vars.bits} - ${this.vars.before})`;
    }
    return this.from_uint(uint_val);
  }

  from_uint(uint_val: string) {
    if (this.type === "address") {
      return `address(uint160(${uint_val}))`;
    } else if (this.type === "bool") {
      return `(${uint_val} > 0)`;
    } else {
      // uint by default
      return uint_val;
    }
  }

  inject(val: string) {
    const uint_val = this.to_uint(val);
    return `(${uint_val} << (256 - ${this.vars.bits})) >> ${this.vars.before}`;
  }

  to_uint(val: string) {
    if (this.type === "address") {
      return `uint(uint160(${val}))`;
    } else if (this.type === "bool") {
      return `uint_of_bool(${val})`;
    } else {
      // uint by default
      return val;
    }
  }
}

class Struct {
  // validate struct_def: correct types & sizes
  static validate(fields_def: field_def[]) {
    const red = (acc: any, field: field_def) => {
      const desc = util.inspect(field);
      if (!["uint", "address", "bool"].includes(field.type)) {
        throw new Error(
          `bad field ${desc}, only allowed types are uint,address and bool`
        );
      }
      if (field.type === "address" && field.bits !== 160) {
        throw new Error(`bad field ${desc}, addresses must have 160 bits`);
      }
      return acc + field.bits;
    };
    const bits = fields_def.reduce(red, 0);
    if (bits > 256) {
      throw new Error(
        `bad fields ${util.inspect(fields_def)}\nbitsize ${bits} > 256`
      );
    }
  }

  name: string;
  Name: string;
  Packed: string;
  Unpacked: string;
  filenames: {src: string, test: string};
  fields: Field[];

  constructor(name: string, fields_def: field_def[], filenamers: (_:Struct) => Struct['filenames']) {
    Struct.validate(fields_def);
    this.name = name;
    this.Name = capitalize(this.name);
    this.Packed = `${this.Name}Packed`;
    this.Unpacked = `${this.Name}Unpacked`;
    this.filenames = filenamers(this);
    this.fields = fields_def.map((data: field_def) => new Field(data));
  }
  unwrap(val: any) {
    return `${this.Packed}.unwrap(${val})`;
  }
  wrap(val: any) {
    return `${this.Packed}.wrap(${val})`;
  }
}

export const make_structs = (struct_defs: {[key:string]: field_def[]}, filenamer: (_:Struct) => Struct['filenames']) => {
  return Object.entries(struct_defs).map(([name, fields_def]) => {
    return new Struct(name, fields_def, filenamer);
  });
};
