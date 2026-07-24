# Integración Next.js ↔ App Foqqus Cashless (Android)

## Cómo funciona el sistema

1. **Next.js** genera un `sessionId` único y construye una URL (deep link) con los parámetros que la app necesita.
2. El usuario abre esa URL (o haces `window.location = url`) → **Android** abre la app Foqqus Pay con un **Intent** y le pasa los query params.
3. La **app Flutter** recibe los datos (`getInitialIntent` / `handleIntent`), ejecuta la acción (por ejemplo READ → lee NFC) y:
   - Escribe el resultado en **Firestore** en `nfcReader/{sessionId}`.
   - Cierra la actividad con `returnToWeb()` (o `sendDataToWeb` si se usa desde WebView con `startActivityForResult`).
4. **Next.js** debe estar escuchando el documento Firestore `nfcReader/{sessionId}` para saber cuándo la app terminó y qué resultado devolvió.

---

## Parámetros del Intent (query params)

La app espera estos query params en la URI (ver `MainActivity.kt` y `_handleIntentData` en `main.dart`):

| Parámetro   | Requerido | Descripción |
|------------|-----------|-------------|
| `accion`   | Sí        | `READ`, `READWRISTBAND`, `CREATE`, `ASSIGN_ACCOUNT`, `UPDATE_STATUS` |
| `timestamp`| Sí        | Marca de tiempo (ej. `Date.now().toString()`) |
| `sessionId`| Sí        | ID único de la sesión (usado como doc ID en Firestore para recibir el resultado) |
| `clientId` | Según acción | Necesario para CREATE y para identificar la cuenta |
| `type`     | Sí        | Tipo de operación (ej. `READ`) |

---

## Esquemas de URL que abre la app (AndroidManifest)

- **Custom scheme:** `foqquscashless://?accion=...&sessionId=...&...`
- **Manillas:** `manillasapp://app?accion=...&sessionId=...&...`
- **App Links (HTTPS):** `https://delicate-cendol-2dc565.netlify.app?accion=...&sessionId=...&...`

En móvil, si la app está instalada, Android abrirá la app; si no, puede abrir el fallback en el navegador.

---

## Función en Next.js: construir URL e iniciar intent

```ts
// utils/cashlessDeepLink.ts

export type CashlessAction = 'READ' | 'READWRISTBAND' | 'CREATE' | 'ASSIGN_ACCOUNT' | 'UPDATE_STATUS';

export interface CashlessIntentParams {
  accion: CashlessAction;
  sessionId: string;
  clientId?: string;
  type?: string;
}

const SCHEMES = {
  foqqus: 'foqquscashless',
  manillas: 'manillasapp://app',
  // Usar tu dominio real en producción para App Links
  https: 'https://delicate-cendol-2dc565.netlify.app',
} as const;

/**
 * Construye la URL de deep link para abrir la app con el intent.
 * Usa sessionId único para poder escuchar el resultado en Firestore.
 */
export function buildCashlessDeepLink(
  params: CashlessIntentParams,
  scheme: keyof typeof SCHEMES = 'foqqus'
): string {
  const { accion, sessionId, clientId, type } = params;
  const timestamp = Date.now().toString();

  const searchParams = new URLSearchParams({
    accion,
    timestamp,
    sessionId,
    ...(clientId != null && { clientId }),
    ...(type != null && { type: type || 'READ' }),
  });

  const base = SCHEMES[scheme];
  if (scheme === 'foqqus') {
    // foqquscashless://?params (sin host)
    return `${base}://?${searchParams.toString()}`;
  }
  if (scheme === 'manillas') {
    return `${base}?${searchParams.toString()}`;
  }
  return `${base}?${searchParams.toString()}`;
}

/**
 * Abre la app (o fallback en navegador).
 * En Android con la app instalada, redirige a la app.
 */
export function openCashlessIntent(
  params: CashlessIntentParams,
  scheme: keyof typeof SCHEMES = 'foqqus'
): void {
  const url = buildCashlessDeepLink(params, scheme);
  window.location.href = url;
}
```

---

## Función en Next.js: escuchar resultado en Firestore

La app escribe en **Firestore** en la colección `nfcReader`, documento con id `sessionId`. Campos relevantes (según `_sendDataToBackend` en `main.dart`):

- `status`: `'completed'` | `'failed'`
- `actionCompleted`: `true` cuando terminó
- `actionResult`: `'success'` | `'failed'`
- `serial`: dato leído (NFC) en caso READ
- `clientIdWritten`, `createAction`, `message` en caso CREATE
- `errorMessage` si falló

Ejemplo de hook/util para escuchar ese documento y devolver el resultado:

```ts
// hooks/useCashlessResult.ts (o lib/firestore-cashless.ts)

import { useEffect, useState } from 'react';
import {
  doc,
  onSnapshot,
  getFirestore,
  DocumentSnapshot,
  DocumentData,
} from 'firebase/firestore';

export interface CashlessResult {
  status: 'completed' | 'failed';
  actionResult?: 'success' | 'failed';
  serial?: string;
  clientIdWritten?: string;
  createAction?: boolean;
  message?: string;
  errorMessage?: string;
  type?: string;
  updatedAt?: unknown;
  completedAt?: unknown;
}

export function useCashlessResult(sessionId: string | null) {
  const [result, setResult] = useState<CashlessResult | null>(null);
  const [loading, setLoading] = useState(!!sessionId);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!sessionId) {
      setLoading(false);
      return;
    }

    const db = getFirestore();
    const docRef = doc(db, 'nfcReader', sessionId);

    const unsubscribe = onSnapshot(
      docRef,
      (snap: DocumentSnapshot<DocumentData>) => {
        if (!snap.exists()) {
          setLoading(false);
          return;
        }
        const data = snap.data();
        setResult({
          status: (data?.status as CashlessResult['status']) ?? 'completed',
          actionResult: data?.actionResult,
          serial: data?.serial,
          clientIdWritten: data?.clientIdWritten,
          createAction: data?.createAction,
          message: data?.message,
          errorMessage: data?.errorMessage,
          type: data?.type,
          updatedAt: data?.updatedAt,
          completedAt: data?.completedAt,
        });
        setLoading(false);
      },
      (err) => {
        setError(err as Error);
        setLoading(false);
      }
    );

    return () => unsubscribe();
  }, [sessionId]);

  return { result, loading, error };
}
```

---

## Flujo completo en una página Next.js

Ejemplo: botón “Leer NFC” que abre la app y muestra el resultado cuando vuelve.

```tsx
// app/leer-nfc/page.tsx (o components/LeerNFC.tsx)

'use client';

import { useState, useCallback } from 'react';
import { buildCashlessDeepLink, openCashlessIntent } from '@/utils/cashlessDeepLink';
import { useCashlessResult } from '@/hooks/useCashlessResult';
import { v4 as uuidv4 } from 'uuid'; // o crypto.randomUUID() si usas Node 19+

export default function LeerNFCPage() {
  const [sessionId, setSessionId] = useState<string | null>(null);

  const { result, loading } = useCashlessResult(sessionId);

  const handleOpenApp = useCallback(() => {
    const id = uuidv4(); // o crypto.randomUUID()
    setSessionId(id);
    openCashlessIntent({
      accion: 'READ',
      sessionId: id,
      type: 'READ',
    });
  }, []);

  return (
    <div>
      <button type="button" onClick={handleOpenApp}>
        Abrir app para leer NFC
      </button>
      {sessionId && (
        <p className="text-sm text-gray-500">
          Session: {sessionId}. Esperando resultado en Firestore...
        </p>
      )}
      {loading && <p>Esperando resultado de la app...</p>}
      {result && (
        <div>
          <p>Estado: {result.status}</p>
          {result.serial && <p>Serial leído: {result.serial}</p>}
          {result.errorMessage && <p>Error: {result.errorMessage}</p>}
        </div>
      )}
    </div>
  );
}
```

---

## Resumen

| Paso | Quién | Qué hace |
|------|--------|----------|
| 1 | Next.js | Genera `sessionId` único y llama a `openCashlessIntent({ accion, sessionId, clientId?, type })`. |
| 2 | Navegador | Redirige a `foqquscashless://?accion=...&sessionId=...&...` (o otro scheme). |
| 3 | Android | Abre la app y pasa el Intent a MainActivity; Flutter recibe los params en `_handleIntentData`. |
| 4 | App | Ejecuta la acción (READ/CREATE/…) y escribe en Firestore `nfcReader/{sessionId}` y luego `returnToWeb()`. |
| 5 | Next.js | Usa `useCashlessResult(sessionId)` (onSnapshot en `nfcReader/{sessionId}`) y cuando `actionCompleted === true` muestra el resultado. |

No es necesario que la app “mande hacia atrás” datos por Intent al navegador: el “retorno” se hace vía **Firestore** usando el mismo `sessionId`. Si más adelante usas la app dentro de un WebView con `startActivityForResult`, el nativo puede además leer el extra `cashlessData` del Intent de resultado e inyectarlo a la web; para una web abierta en Chrome/Safari, Firestore es la vía correcta.
