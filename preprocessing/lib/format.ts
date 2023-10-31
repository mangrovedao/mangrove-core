// template tag that converts array to separate lines but keeps the current
// indent level
export const format = (strings: TemplateStringsArray, ...nuggets: any[]) => {
  let output = "";
  strings.forEach((str, i) => {
    output += str;
    if (i + 1 == strings.length) return;
    if (nuggets[i] instanceof Array) {
      const indent = /(?:\n|^)(.*)$/.exec(output)?.[1]?.length ?? 0;
      // don't indent first line, don't indent empty lines
      const with_indent = nuggets[i].map(
        (line, i) =>
          `${line.match(/\S/) && i > 0 ? " ".repeat(indent) : ""}${line}`
      );
      output += with_indent.join("\n");
    } else {
      output += nuggets[i];
    }
  });

  return output;
};

// takes an array of arrays all of the same length
// returns an array of strings with aligned columns (except the last)
// example: [['s','= 123'],['long',''= 2']] becomes ['s   = 123','long=2']
export const tabulate = (table: string[][]) => {
  const zeroes = Array((table[0] ?? []).length).fill(0);
  const maxes = table.reduce(
    (acc, row) => acc.map((max, i) => Math.max(max, row[i].length)),
    zeroes
  );
  const tab = (cell, i) => " ".repeat(Math.max(maxes[i] - cell.length, 0));
  return table.map((row) =>
    row
      .map((cell, i) => {
        const last = i + 1 >= row.length;
        return `${cell}${last ? "" : tab(cell, i)}`;
      })
      .join("")
  );
};
