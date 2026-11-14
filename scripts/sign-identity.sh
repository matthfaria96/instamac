#!/usr/bin/env bash
# sign-identity.sh -- a identidade com que os scripts assinam código do Instamac.
#
# $INSTAMAC_SIGN_ID, se definida; senão "Instamac Local Signing" quando essa identidade
# (certificado autoassinado, só para assinar código neste Mac) está no chaveiro; senão
# "-" (ad-hoc). Com a identidade estável, o requisito de assinatura do runtime é
# `identifier "dev.instamac.runtime" and certificate leaf = H"…"`: igual em toda
# reassinatura, e o macOS mantém as permissões já dadas (câmera, microfone). Ad-hoc, cada
# reassinatura muda o cdhash e o macOS pede tudo de novo.
if [ -n "${INSTAMAC_SIGN_ID:-}" ]; then echo "$INSTAMAC_SIGN_ID"; exit 0; fi
if security find-identity -p codesigning 2>/dev/null | grep -q '"Instamac Local Signing"'; then
    echo "Instamac Local Signing"
else
    echo "-"
fi
