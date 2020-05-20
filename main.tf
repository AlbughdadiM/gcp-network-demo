provider "google" {
  project = "xxx"
}

resource "google_compute_network" "my_vpc" {
  name = "my-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "my_vpc_allow_ssh" {
  name = "my-vpc-allow-ssh"
  network = google_compute_network.my_vpc.name
  allow {
    protocol = "tcp"
    ports = [
      22
    ]
  }
  source_ranges = [
    "0.0.0.0/0"
  ]
}

resource "google_compute_subnetwork" "europe_west1" {
  ip_cidr_range = "10.0.0.0/24"
  region = "europe-west1"
  name = "europe-west1"
  network = google_compute_network.my_vpc.name
}

resource "google_compute_router" "my_vpc_router" {
  name = "my-vpc-router"
  network = google_compute_network.my_vpc.name
  region = "europe-west1"
}

resource "google_compute_router_nat" "my_vpc_nat" {
  name = "my-vpc-nat"
  nat_ip_allocate_option = "AUTO_ONLY"
  router = google_compute_router.my_vpc_router.name
  region = google_compute_router.my_vpc_router.region
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance" "public_ip_instance" {
  machine_type = "n1-standard-1"
  name = "public-ip-instance"
  zone = "europe-west1-b"
  metadata_startup_script = "sudo apt-get update && sudo apt-get install nginx -y"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.europe_west1.name
    access_config {}
  }
}

resource "google_compute_instance" "private_ip_instance" {
  machine_type = "n1-standard-1"
  name = "private-ip-instance"
  zone = "europe-west1-b"
  metadata_startup_script = "sudo apt-get update && sudo apt-get install nginx -y"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.europe_west1.name
  }
}

# Configure global load balancer

data "google_compute_lb_ip_ranges" "google_lb_ip_ranges" {}

resource "google_compute_firewall" "lb" {
  name = "my-vpc-allow-google-lb"
  network = google_compute_network.my_vpc.id
  allow {
    protocol = "tcp"
    ports = [
      80
    ]
  }
  source_ranges = data.google_compute_lb_ip_ranges.google_lb_ip_ranges.http_ssl_tcp_internal
}

resource "google_compute_instance_group" "my_instance_group" {
  name = "my-instance-group"
  network = google_compute_network.my_vpc.id
  zone = "europe-west1-b"
  instances = [
    google_compute_instance.private_ip_instance.self_link,
    google_compute_instance.public_ip_instance.self_link
  ]
  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_global_forwarding_rule" "my_global_fw_rule" {
  name = "my-global-fw-rule"
  target = google_compute_target_http_proxy.my_target_http_proxy.id
  port_range = "80"
}

resource "google_compute_target_http_proxy" "my_target_http_proxy" {
  name = "my-target-http-proxy"
  url_map = google_compute_url_map.my_url_map.id
}

resource "google_compute_url_map" "my_url_map" {
  name = "my-url-map"
  default_service = google_compute_backend_service.my_backend_service.id
}

resource "google_compute_backend_service" "my_backend_service" {
  name = "my-backend-service"
  port_name = "http"
  protocol = "HTTP"
  health_checks = [
    google_compute_http_health_check.my_health_check.id
  ]
  backend {
    group = google_compute_instance_group.my_instance_group.id
  }
}

resource "google_compute_http_health_check" "my_health_check" {
  name = "my-health-check"
  request_path = "/"
  port = 80
}