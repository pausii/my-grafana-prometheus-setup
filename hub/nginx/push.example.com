# ============================================================
# push.example.com — remote_write receiver for ephemeral servers
# ============================================================
# Put this behind a CDN/proxy that terminates TLS (Cloudflare in
# the original setup). That matters for more than encryption: the
# proxy also provides an IPv4 address, so an IPv4-only server can
# reach an IPv6-only origin.
#
# PRINCIPLE: open as narrow a hole as possible. Prometheus has
# several dangerous endpoints — /api/v1/query reads EVERY metric,
# /-/reload reloads configuration. So this vhost forwards exactly
# ONE path with exactly ONE method; everything else is 404.

server {
    listen 80;
    listen [::]:80;
    server_name push.example.com;

    # Format push_log records CF-Connecting-IP — the real client
    # address behind the proxy. See conf.d/push-log-format.conf.
    access_log /var/log/nginx/push-access.log push_log;
    error_log  /var/log/nginx/push-error.log;

    server_tokens off;

    location = /api/v1/write {
        # remote_write only ever uses POST. Other methods are
        # rejected before authentication is even checked.
        limit_except POST {
            deny all;
        }

        auth_basic           "metrics push";
        auth_basic_user_file /etc/nginx/push.htpasswd;

        # Forwarded to the SECOND Prometheus (9091), not the main one.
        proxy_pass http://127.0.0.1:9091/api/v1/write;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # remote_write bodies are kilobytes, but leave headroom for
        # an agent flushing a backlog after a disconnection.
        client_max_body_size 32m;
        proxy_read_timeout   60s;
        proxy_request_buffering off;
    }

    # Every other path does not exist. That includes
    # /api/v1/query, /graph, /-/reload and /metrics — none of them
    # should ever be reachable from outside.
    location / {
        return 404;
    }
}
