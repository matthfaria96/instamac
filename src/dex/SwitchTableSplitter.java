// SwitchTableSplitter -- reconhece o formato "tabela de strings" que o divisor
// forward-only nao consegue cortar e planeja a distribuicao do dispatcher.
//
// O CASO REAL (Instagram 455, X/0000.A00, 77.269 bytes): um unico `switch` com
// 7.738 casos, cada caso `const-string vX, "..."` seguido de `return-object vX`.
// Nenhuma outra familia de instrucao aparece. O divisor recusa porque a parte
// que herda os destinos do switch recebe milhares de entry stubs e estoura o
// teto de 65.535 bytes (medido: 6.211 entradas, 83.346 bytes).
//
// A SAIDA: particionar os VALORES do switch em faixas. Cada parte vira um
// metodo estatico com o SEU switch (tabela menor) e os corpos dos seus casos;
// o metodo original vira um driver que escolhe a parte pela faixa. Nenhum valor
// atravessa partes: cada caso termina em return e so usa a chave.
//
// Esta classe, por enquanto, so PLANEJA (Etapa E1 de docs/F1-DESIGN.md). A
// emissao (E2) usa CodeWriter.tableSwitch/lookupSwitch com os labels dos corpos.
package com.macapk.dex;

import java.util.ArrayList;
import java.util.List;

final class SwitchTableSplitter {

    private SwitchTableSplitter() {}

    /** Quantos casos por parte. 7.738 casos / 2.000 = 4 partes de ~26 KB. */
    static final int CASES_PER_PART = 2000;

    /** Plano de distribuicao, ou null quando o metodo nao e uma tabela pura. */
    static final class Plan {
        /** Indices em `norm` do unico switch e do fim do metodo. */
        final int switchIndex;
        /** Numero de casos do switch (== switchTargets.length). */
        final int cases;
        /** Faixas [fromCase, toCase) por parte. */
        final List<int[]> ranges;

        Plan(int switchIndex, int cases, List<int[]> ranges) {
            this.switchIndex = switchIndex;
            this.cases = cases;
            this.ranges = ranges;
        }

        int parts() { return ranges.size(); }
    }

    /**
     * Um metodo so entra aqui quando NAO existe fluxo a preservar alem do
     * switch: nenhuma outra instrucao com semantica de salto, nada que escreva
     * estado. Assim cada caso e auto-contido e pode ir para qualquer parte sem
     * frame e sem parametros.
     */
    static Plan detect(List<TypeInference.Insn> norm) {
        final int n = norm.size();
        int switchIndex = -1;
        int cases = 0;
        for (int i = 0; i < n; i++) {
            TypeInference.Insn in = norm.get(i);
            int fam = TypeInference.familyOf(in.opcode);
            if (fam == TypeInference.F_SWITCH) {
                if (switchIndex >= 0) return null;            // mais de um dispatcher
                switchIndex = i;
                cases = in.switchTargets.length;
                if (cases == 0) return null;
                continue;
            }
            switch (fam) {
                case TypeInference.F_CONST_STRING:
                case TypeInference.F_RETURN:
                case TypeInference.F_NOP:
                    continue;                                  // corpos e retornos
                default:
                    return null;                               // qualquer outra coisa: nao e tabela pura
            }
        }
        if (switchIndex < 0 || cases < CASES_PER_PART * 2) return null;
        // Estrutura esperada: 1 switch + (const-string, return) por caso.
        if (n < cases * 2) return null;

        List<int[]> ranges = new ArrayList<>();
        for (int from = 0; from < cases; from += CASES_PER_PART) {
            int to = Math.min(cases, from + CASES_PER_PART);
            ranges.add(new int[]{ from, to });
        }
        return new Plan(switchIndex, cases, ranges);
    }

    /** Linha de diagnostico, no formato dos outros logs do tradutor. */
    static String describe(Plan p, String methodTag) {
        StringBuilder b = new StringBuilder();
        b.append("[switch-split] ").append(methodTag).append(": ").append(p.cases)
         .append(" casos, ").append(p.parts()).append(" partes:");
        for (int[] r : p.ranges) b.append(" [").append(r[0]).append(',').append(r[1]).append(')');
        return b.toString();
    }
}
