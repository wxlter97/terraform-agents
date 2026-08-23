"""Lambda proxy del Módulo 6: expone el harness del Módulo 5 (el agente) como
un endpoint HTTP simple, vía API Gateway.

A diferencia de las tool Lambdas (Módulo 3/5), esta Lambda no es invocada
*por* el agente — es la que invoca *al* agente, usando el método `InvokeHarness`
del cliente `bedrock-agentcore` de boto3 (no está en el AWS CLI todavía, pero
sí en el boto3 que trae el runtime de Lambda — verificado antes de escribir
este código, ver modules/06-api-gateway.md).

`InvokeHarness` devuelve un stream de eventos al estilo Bedrock Converse
Stream (`messageStart`, `contentBlockDelta`, `messageStop`, ...), no un JSON
plano — hay que iterarlo y acumular el texto.
"""

import json
import os
import uuid

import boto3

bedrock_agentcore = boto3.client("bedrock-agentcore")
HARNESS_ARN = os.environ["HARNESS_ARN"]


def lambda_handler(event, context):
    body = json.loads(event.get("body") or "{}")
    message = body.get("message", "")
    if not message:
        return _response(400, {"error": "Falta 'message' en el body."})

    # Reusar el mismo session_id en llamadas sucesivas mantiene la
    # conversación — si no viene ninguno, arrancamos una sesión nueva.
    session_id = body.get("session_id") or str(uuid.uuid4())

    response = bedrock_agentcore.invoke_harness(
        harnessArn=HARNESS_ARN,
        runtimeSessionId=session_id,
        messages=[{"role": "user", "content": [{"text": message}]}],
    )

    reply_parts = []
    stop_reason = None
    usage = None

    for chunk in response["stream"]:
        if "contentBlockDelta" in chunk:
            delta = chunk["contentBlockDelta"].get("delta", {})
            if "text" in delta:
                reply_parts.append(delta["text"])
        elif "messageStop" in chunk:
            stop_reason = chunk["messageStop"].get("stopReason")
        elif "metadata" in chunk:
            usage = chunk["metadata"].get("usage")
        elif "validationException" in chunk:
            return _response(400, {"error": chunk["validationException"].get("message")})
        elif "internalServerException" in chunk:
            return _response(502, {"error": chunk["internalServerException"].get("message")})
        elif "runtimeClientError" in chunk:
            return _response(502, {"error": chunk["runtimeClientError"].get("message")})

    return _response(
        200,
        {
            "session_id": session_id,
            "reply": "".join(reply_parts),
            "stop_reason": stop_reason,
            "usage": usage,
        },
    )


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
