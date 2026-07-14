import nodemailer from "nodemailer";

export const sendMailImpl = (cfg, mail, cb) => () => {
	if (!cfg.host) {
		cb(new Error("SMTP is not configured (SMTP_HOST unset)"))();
		return;
	}

	const transport = nodemailer.createTransport({
		host: cfg.host,
		port: cfg.port || 587,
		secure: false,
		requireTLS: true,
		auth: cfg.user && cfg.pass ? { user: cfg.user, pass: cfg.pass } : undefined,
	});

	transport
		.sendMail({
			from: cfg.from || cfg.user || undefined,
			to: mail.to,
			subject: mail.subject,
			text: mail.text,
		})
		.then(() => cb(null)())
		.catch((err) => cb(err)());
};
