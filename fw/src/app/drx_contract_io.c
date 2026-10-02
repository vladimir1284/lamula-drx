/* Implementacion de fw/include/drx_contract_io.h.
 *
 * Sin dependencias de Xilinx ni de FreeRTOS a proposito: este fichero se
 * compila DOS veces, cruzado para el Cortex-A9 dentro del flujo de Vitis
 * (tcl/gen_bsp.tcl) y nativo para el host en fw/Makefile, donde
 * fw/tests/test_contract_io.py lo contrasta contra la implementacion de Python
 * generada del mismo esquema. Si aparece aqui un `xil_printf` o un `Xil_In32`,
 * la mitad de host deja de compilar y se pierde esa comprobacion.
 */
#include "drx_contract_io.h"

#include <string.h>

drx_dsp_error_t DrxFrame_ErrorCode(DrxFrameStatus status)
{
    switch (status) {
    case DRX_FRAME_BAD_VERSION:
        return DRX_DSP_ERROR_UNSUPPORTED_VERSION;
    case DRX_FRAME_UNKNOWN_TYPE:
        return DRX_DSP_ERROR_UNKNOWN_MESSAGE;
    case DRX_FRAME_BAD_LENGTH:
    case DRX_FRAME_BAD_FLAGS:
        /* `flags` reservado y distinto de 0 es, en la practica, una trama cuyo
         * formato no es el que esta version declara. El contrato no tiene un
         * codigo propio para eso y no se le inventa uno aqui: inventarlo seria
         * cambiar el contrato desde el firmware. `bad_length` es el codigo del
         * esquema que cubre "la trama no cuadra con lo declarado". */
        return DRX_DSP_ERROR_BAD_LENGTH;
    case DRX_FRAME_OK:
    case DRX_FRAME_NEED_MORE:
    case DRX_FRAME_BAD_MAGIC:
    case DRX_FRAME_TOO_LARGE:
    default:
        return DRX_DSP_ERROR_OK;
    }
}

uint32_t DrxFrame_BodySize(uint8_t msg_type)
{
    switch (msg_type) {
    case DRX_DSP_MSG_RAY:
        return (uint32_t)sizeof(drx_dsp_ray_t);
    case DRX_DSP_MSG_STATUS:
        return (uint32_t)sizeof(drx_dsp_status_t);
    case DRX_DSP_MSG_CONFIG:
        return (uint32_t)sizeof(drx_dsp_config_t);
    case DRX_DSP_MSG_CONFIG_ACK:
        return (uint32_t)sizeof(drx_dsp_config_ack_t);
    case DRX_DSP_MSG_AFC:
        return (uint32_t)sizeof(drx_dsp_afc_t);
    case DRX_DSP_MSG_TEST_STIMULUS_SELECT:
        return (uint32_t)sizeof(drx_dsp_test_stimulus_select_t);
    default:
        return 0u;
    }
}

bool DrxFrame_IsDownstream(uint8_t msg_type)
{
    switch (msg_type) {
    case DRX_DSP_MSG_CONFIG:
    case DRX_DSP_MSG_AFC:
    case DRX_DSP_MSG_TEST_STIMULUS_SELECT:
        return true;
    default:
        return false;
    }
}

/* Solo `ray` lleva carga detras del struct. Que lo diga una funcion y no un
 * `if` suelto deja el sitio exacto donde tocar si un mensaje futuro tambien la
 * lleva. */
static bool body_takes_variable_payload(uint8_t msg_type)
{
    return msg_type == DRX_DSP_MSG_RAY;
}

size_t DrxFrame_Encode(uint8_t *out, size_t out_cap, uint8_t msg_type,
                       const void *body, size_t body_len,
                       const void *payload, size_t payload_len)
{
    uint32_t expected_body = DrxFrame_BodySize(msg_type);

    if (out == NULL || body == NULL || expected_body == 0u) {
        return 0u;
    }
    if (body_len != (size_t)expected_body) {
        return 0u;
    }
    if (payload_len != 0u && (payload == NULL || !body_takes_variable_payload(msg_type))) {
        return 0u;
    }

    size_t total = (size_t)DRX_FRAME_HEADER_SIZE + body_len + payload_len;
    if (total > out_cap) {
        return 0u;
    }

    drx_dsp_header_t header;
    header.magic = DRX_DSP_MAGIC;
    header.version_major = DRX_DSP_VERSION_MAJOR;
    header.version_minor = DRX_DSP_VERSION_MINOR;
    header.msg_type = msg_type;
    header.flags = 0u;
    /* La regla normativa del esquema: el struct del mensaje MAS su carga
     * variable. Nunca 0 -- ver el doc de payload_len en el esquema. */
    header.payload_len = (uint32_t)(body_len + payload_len);

    memcpy(out, &header, DRX_FRAME_HEADER_SIZE);
    memcpy(out + DRX_FRAME_HEADER_SIZE, body, body_len);
    if (payload_len != 0u) {
        memcpy(out + DRX_FRAME_HEADER_SIZE + body_len, payload, payload_len);
    }
    return total;
}

void DrxParser_Init(DrxParser *parser, uint8_t *buf, size_t cap)
{
    memset(parser, 0, sizeof(*parser));
    parser->buf = buf;
    parser->cap = cap;
    parser->status = DRX_FRAME_NEED_MORE;
}

void DrxParser_Reset(DrxParser *parser)
{
    parser->len = 0u;
    parser->have_header = false;
    parser->status = DRX_FRAME_NEED_MORE;
}

/* Valida la cabecera ya acumulada. No mira el cuerpo: eso no ha llegado aun. */
static DrxFrameStatus validate_header(const DrxParser *parser,
                                      const drx_dsp_header_t *header)
{
    if (header->magic != DRX_DSP_MAGIC) {
        return DRX_FRAME_BAD_MAGIC;
    }
    if (header->version_major != DRX_DSP_VERSION_MAJOR) {
        return DRX_FRAME_BAD_VERSION;
    }
    /* `version_minor` NO se compara: el esquema lo define como compatible hacia
     * atras dentro del mismo major. Un par remoto mas nuevo puede mandar
     * mensajes que aqui se rechazan por msg_type desconocido, que es el
     * mecanismo correcto, pero su cabecera es valida. */
    if (header->flags != 0u) {
        return DRX_FRAME_BAD_FLAGS;
    }
    if (!DrxFrame_IsDownstream(header->msg_type)) {
        return DRX_FRAME_UNKNOWN_TYPE;
    }

    uint32_t body = DrxFrame_BodySize(header->msg_type);
    if (body_takes_variable_payload(header->msg_type)) {
        if (header->payload_len < body) {
            return DRX_FRAME_BAD_LENGTH;
        }
    } else if (header->payload_len != body) {
        return DRX_FRAME_BAD_LENGTH;
    }

    if ((size_t)DRX_FRAME_HEADER_SIZE + (size_t)header->payload_len > parser->cap) {
        return DRX_FRAME_TOO_LARGE;
    }
    return DRX_FRAME_OK;
}

size_t DrxParser_Push(DrxParser *parser, const uint8_t *data, size_t n,
                      DrxParser_OnMessage on_message, void *user)
{
    size_t consumed = 0u;

    while (consumed < n) {
        /* Fase 1: completar la cabecera comun. */
        if (!parser->have_header) {
            size_t need = (size_t)DRX_FRAME_HEADER_SIZE - parser->len;
            size_t take = (n - consumed < need) ? (n - consumed) : need;

            memcpy(parser->buf + parser->len, data + consumed, take);
            parser->len += take;
            consumed += take;

            if (parser->len < (size_t)DRX_FRAME_HEADER_SIZE) {
                parser->status = DRX_FRAME_NEED_MORE;
                break;
            }

            memcpy(&parser->header, parser->buf, DRX_FRAME_HEADER_SIZE);
            DrxFrameStatus status = validate_header(parser, &parser->header);
            if (status != DRX_FRAME_OK) {
                /* Parada dura. Tras una cabecera invalida no se sabe donde
                 * empieza el mensaje siguiente, asi que saltarse esta trama
                 * seria adivinar. El llamante decide: contestar con
                 * DrxFrame_ErrorCode() y rearmar, o cerrar. */
                parser->status = status;
                parser->rejected++;
                break;
            }
            parser->have_header = true;
            parser->status = DRX_FRAME_NEED_MORE;
        }

        /* Fase 2: completar el cuerpo. */
        size_t total = (size_t)DRX_FRAME_HEADER_SIZE + (size_t)parser->header.payload_len;
        size_t need = total - parser->len;
        size_t take = (n - consumed < need) ? (n - consumed) : need;

        memcpy(parser->buf + parser->len, data + consumed, take);
        parser->len += take;
        consumed += take;

        if (parser->len < total) {
            parser->status = DRX_FRAME_NEED_MORE;
            break;
        }

        if (on_message != NULL) {
            on_message(&parser->header, parser->buf + DRX_FRAME_HEADER_SIZE,
                       parser->header.payload_len, user);
        }
        parser->accepted++;
        parser->len = 0u;
        parser->have_header = false;
        parser->status = DRX_FRAME_OK;
    }

    return consumed;
}
