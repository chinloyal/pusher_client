package com.github.chinloyal.pusher_client.core.utils

import com.pusher.client.util.ConnectionFactory
import org.json.JSONObject

class JsonEncodedConnectionFactory : ConnectionFactory() {
    override fun getCharset(): String {
        return "UTF-8";
    }

    override fun getContentType(): String {
        return "application/json";
    }

    override fun getBody(): String {
        val data: JSONObject = JSONObject();
        data.put("channel_name", channelName);
        data.put("socket_id", socketId);

        return data.toString();
    }
}