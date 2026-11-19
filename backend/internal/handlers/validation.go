// RSS2 — Agregador multilingüe de noticias RSS
// Copyright (c) 2026 Dinámicas Electrónicas <dinamicas.electronicas@gmail.com>
// SPDX-License-Identifier: MIT

package handlers

func validatePageParams(page, perPage, defaultPerPage, maxPerPage int) (int, int) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = defaultPerPage
	}
	if perPage > maxPerPage {
		perPage = maxPerPage
	}
	return page, perPage
}