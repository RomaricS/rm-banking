// Turns noisy bank labels into stable merchant keys and readable names.
// Works for US/CA labels ("SQ *BLUE BOTTLE 0423", "TST* TACO 12") and FR/EU labels
// ("ACHAT CB MONOPRIX 12/11 CARTE 4821", "PRLV SEPA EDF", "VIR INST M DUPONT").

const PREFIXES = [
  // FR
  /^achat\s+cb\s+/i, /^paiement\s+(par\s+)?carte\s+/i, /^paiement\s+cb\s+/i, /^cb\s*\*?\s*/i, /^carte\s+(x?\d{4}\s+)?/i,
  /^prlv\s+(sepa\s+)?/i, /^prelevement\s+(sepa\s+)?/i, /^vir(ement)?\s+(sepa\s+)?(inst(antane)?\s+)?(recu\s+|emis\s+)?/i,
  /^retrait\s+(dab\s+)?/i, /^facture\s+carte\s+/i,
  // UK / DE
  /^card\s+payment\s+(to\s+)?/i, /^kartenzahlung\s+/i, /^lastschrift\s+/i, /^ueberweisung\s+|^überweisung\s+/i,
  // US/CA processors
  /^sq\s*\*\s*/i, /^tst\s*\*\s*/i, /^sp\s*\*?\s+/i, /^paypal\s*\*\s*/i, /^pp\s*\*\s*/i, /^dd\s*\*?\s*(doordash\s*)?/i,
  /^pos\s+(purchase\s+)?/i, /^debit\s+card\s+purchase\s+/i, /^idp\s+purchase\s*-?\s*/i, /^interac\s+(purchase\s*-?\s*)?/i,
  /^purchase\s+/i, /^recurring\s+payment\s+/i,
];

const NOISE = [
  /\b\d{2}[/.-]\d{2}([/.-]\d{2,4})?\b/g,  // dates 12/11, 12.11.26
  /\bcarte\s+x?\d{4}\b/gi,               // CARTE 4821
  /\bx{2,}\d{2,4}\b/gi,                  // XXXX1234
  /#\s?\d+/g,                            // #1234 store numbers
  /\b\d{3,}\b/g,                         // long numbers
  /\b(fr|us|ca|gb|de)\b$/i,              // trailing country
  /\*+/g,
  /[^\p{L}\p{N}&' ]+/gu,
];

export function stripLabel(raw: string): string {
  let s = raw.trim().replace(/\s+/g, " ");
  for (let i = 0; i < 3; i++) {
    const before = s;
    for (const p of PREFIXES) s = s.replace(p, "");
    if (s === before) break;
  }
  for (const n of NOISE) s = s.replace(n, " ");
  return s.replace(/\s+/g, " ").trim();
}

/** Stable key used by rules: lowercase, accents removed, first 3 meaningful words. */
export function merchantKey(nameOrLabel: string): string {
  const s = stripLabel(nameOrLabel)
    .normalize("NFD").replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
  const words = s.split(" ").filter((w) => w.length > 1 && !["the", "inc", "llc", "ltd", "sa", "sas", "sarl"].includes(w));
  return words.slice(0, 3).join(" ") || s;
}

/** Readable merchant name for display when Plaid doesn't give one. */
export function displayName(raw: string): string {
  const s = stripLabel(raw);
  if (!s) return raw.trim();
  return s.split(" ").map((w) => (w.length <= 3 && w === w.toUpperCase() && /[A-Z]/.test(w)) ? w : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(" ");
}
