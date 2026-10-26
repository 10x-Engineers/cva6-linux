/*
 * LED/switch CGI for the Arty GPIO (Xilinx AXI GPIO at 0x40000000).
 * LD4..LD7 are channel-1 bits 4..7, SW0..SW3 are channel-2 bits 4..7.
 *   /cgi-bin/led              read state
 *   /cgi-bin/led?toggle=N     toggle LED N (0..3)
 *   /cgi-bin/led?all=on|off   all LEDs on/off
 *   /cgi-bin/led?follow=1|0   LEDs mirror the switches (background process)
 * Replies with JSON: leds and switches as 4-bit masks, follow flag, uptime.
 *
 * Written in C rather than shell: at 25 MHz every fork/exec costs about a
 * second, and a shell CGI needs several.
 */
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <unistd.h>

#define GPIO_BASE 0x40000000
#define LED_DATA  0 /* word offsets */
#define SW_DATA   2

static const char state_file[] = "/tmp/leds";
static const char pid_file[] = "/tmp/led-follow.pid";
static volatile uint32_t *gpio;

static int read_int(const char *path)
{
	FILE *f = fopen(path, "r");
	int v = 0;

	if (f) {
		if (fscanf(f, "%d", &v) != 1)
			v = 0;
		fclose(f);
	}
	return v;
}

static void write_int(const char *path, int v)
{
	FILE *f = fopen(path, "w");

	if (f) {
		fprintf(f, "%d\n", v);
		fclose(f);
	}
}

static unsigned switches(void)
{
	return (gpio[SW_DATA] >> 4) & 15;
}

static void set_leds(unsigned v)
{
	gpio[LED_DATA] = (v & 15) << 4;
	write_int(state_file, v & 15);
}

static pid_t follower(void)
{
	pid_t pid = read_int(pid_file);

	return (pid > 0 && kill(pid, 0) == 0) ? pid : 0;
}

static void stop_follow(void)
{
	pid_t pid = follower();

	if (pid) {
		kill(pid, SIGTERM);
		/* Keep the LEDs as the switches left them. */
		set_leds(switches());
	}
	unlink(pid_file);
}

static void start_follow(void)
{
	pid_t pid;
	int fd;

	if (follower())
		return;
	pid = fork();
	if (pid == 0) {
		/* Drop the CGI pipe so httpd can finish the request. */
		setsid();
		fd = open("/dev/null", O_RDWR);
		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		for (;;) {
			gpio[LED_DATA] = switches() << 4;
			usleep(50000);
		}
	}
	if (pid > 0)
		write_int(pid_file, pid);
}

int main(void)
{
	const char *q = getenv("QUERY_STRING");
	struct sysinfo si;
	unsigned leds;
	int fd, n;

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	gpio = fd < 0 ? MAP_FAILED :
		mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, GPIO_BASE);
	if (gpio == MAP_FAILED) {
		printf("Status: 500\r\nContent-Type: text/plain\r\n\r\ncannot map GPIO\n");
		return 1;
	}

	if (!q)
		q = "";
	if (sscanf(q, "toggle=%d", &n) == 1 && n >= 0 && n < 4) {
		stop_follow();
		set_leds(read_int(state_file) ^ (1u << n));
	} else if (!strcmp(q, "all=on")) {
		stop_follow();
		set_leds(15);
	} else if (!strcmp(q, "all=off")) {
		stop_follow();
		set_leds(0);
	} else if (!strcmp(q, "follow=1")) {
		start_follow();
	} else if (!strcmp(q, "follow=0")) {
		stop_follow();
	}

	n = follower() != 0;
	leds = n ? switches() : (unsigned)read_int(state_file) & 15;
	sysinfo(&si);
	printf("Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n"
	       "{\"leds\":%u,\"switches\":%u,\"follow\":%d,\"uptime\":%ld}\n",
	       leds, switches(), n, si.uptime);
	return 0;
}
