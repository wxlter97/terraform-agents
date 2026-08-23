"""Tool Lambda del agente, expuesta como target de AgentCore Gateway (Módulo
5): crea un ticket de soporte.

Contrato de evento distinto al de Bedrock Agents Classic: el Gateway invoca
esta función pasando las propiedades del input_schema directamente como
`event` (acá, `{"description": "..."}"`) — sin el wrapper `parameters` /
`actionGroup` que usaba el action group de Bedrock Agents Classic — y espera
de vuelta un JSON plano, sin el wrapper `_agent_response()` de antes. Ver
modules/05-bedrock-agent.md para el porqué del cambio.
"""

import os
import time
import uuid

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TICKETS_TABLE_NAME"])


def lambda_handler(event, context):
    description = event.get("description", "")

    ticket_id = str(uuid.uuid4())
    table.put_item(
        Item={
            "ticket_id": ticket_id,
            "description": description,
            "status": "open",
            "created_at": int(time.time()),
        }
    )

    return {"ticket_id": ticket_id, "status": "open"}
